import SwiftUI
import UIKit
import Observation
import QuartzCore

/// Zoom (1 = the whole picture fits) and pan (points) for the board.
struct ArrowCamera: Equatable {
    var zoom: CGFloat = 1
    var panX: CGFloat = 0
    var panY: CGFloat = 0

    init(_ zoom: CGFloat = 1, _ panX: CGFloat = 0, _ panY: CGFloat = 0) {
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
    }
}

/// Where the picture sits on screen for a view size and camera. Sizes in points (`density` = 1).
final class ArrowLayout {
    /// Small boards stop growing here, so the first levels don't fill the screen with giant arrows.
    static let MAX_CELL: CGFloat = 34

    let size: CGSize
    let width: Int
    let height: Int
    let density: CGFloat
    let fitCell: CGFloat
    let cell: CGFloat
    let origin: CGPoint

    init(_ size: CGSize, _ width: Int, _ height: Int, _ camera: ArrowCamera, _ density: CGFloat = 1) {
        self.size = size
        self.width = width
        self.height = height
        self.density = density
        fitCell = max(1, min(ArrowLayout.MAX_CELL * density, (size.width - 24 * density) / CGFloat(width + 2), (size.height - 24 * density) / CGFloat(height + 2)))
        cell = fitCell * camera.zoom
        origin = CGPoint(x: (size.width - CGFloat(width) * cell) / 2 + camera.panX, y: (size.height - CGFloat(height) * cell) / 2 + camera.panY)
    }

    /// Up to 6× or 28 dp cells, whichever comes first.
    var maxZoom: CGFloat { max(1, min(6, 28 * density / fitCell)) }
    /// Dense boards open zoomed in so cells are at least 9 dp.
    var startZoom: CGFloat { fitCell < 9 * density ? min(maxZoom, 9 * density / fitCell) : 1 }

    func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * cell, y: origin.y + p.y * cell) }
    func cellSpace(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) / cell, y: (p.y - origin.y) / cell) }

    /// Keeps at least part of the picture on screen.
    func clamped(_ c: ArrowCamera) -> ArrowCamera {
        let cl = fitCell * c.zoom
        let limitX = max(0, (CGFloat(width) * cl - size.width) / 2 + 60 * density)
        let limitY = max(0, (CGFloat(height) * cl - size.height) / 2 + 60 * density)
        return ArrowCamera(c.zoom, min(max(c.panX, -limitX), limitX), min(max(c.panY, -limitY), limitY))
    }
}

/**
 * The playing board. Handles tap, hold-to-aim, pan and pinch, with precision hit-testing on dense
 * boards. Resting arrows and dots live in a cached layer of device-scale tiles under one transform,
 * so panning and zooming never redraw them (the Android board redraws every arrow each frame);
 * only moving arrows are drawn per frame.
 */
struct ArrowBoardView: UIViewRepresentable {
    let session: ArrowJamSession
    let theme: ArrowTheme
    let showGrid: Bool
    /// Bumped by the Fit button: eases back to the whole picture.
    let fitRequest: Int

    init(_ session: ArrowJamSession, _ theme: ArrowTheme, _ showGrid: Bool, _ fitRequest: Int) {
        self.session = session
        self.theme = theme
        self.showGrid = showGrid
        self.fitRequest = fitRequest
    }

    func makeUIView(context: Context) -> ArrowBoardUIView { ArrowBoardUIView() }

    func updateUIView(_ view: ArrowBoardUIView, context: Context) {
        view.configure(session, theme, showGrid, fitRequest)
    }

    static func dismantleUIView(_ view: ArrowBoardUIView, coordinator: ()) { view.stop() }
}

// MARK: - The board view

final class ArrowBoardUIView: UIView {
    // Configuration
    private(set) var session: ArrowJamSession?
    private var theme = ArrowTheme.night
    private var showGrid = false
    private var fitRequest = 0

    // Camera
    private var camera = ArrowCamera()
    private var didSetStart = false
    private var viewSize = CGSize.zero
    private var cameraAnimation: (from: ArrowCamera, to: ArrowCamera, start: Double, duration: Double)?

    // Clock
    private var link: CADisplayLink?
    private var now = nowSeconds()
    private var overlayWasActive = true

    // Session events (Kotlin LaunchedEffect keys)
    private var seenHintTick = 0
    private var seenBumpTick = 0
    private var seenWon = false
    private var observing: ArrowJamSession?

    // Static layer
    private let tileRoot = CALayer()
    private var level: ArrowTileLevel?
    private var pendingLevel: ArrowTileLevel?
    private var scene = ArrowStaticScene()

    // Layers on top
    private let overlay = ArrowOverlayView()
    private let minimap = ArrowMinimapView()

    // Gesture
    private var gesture: ArrowGesture?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        clipsToBounds = true
        backgroundColor = .clear
        isOpaque = false
        tileRoot.anchorPoint = .zero
        tileRoot.actions = ArrowTileLevel.noActions
        layer.addSublayer(tileRoot)
        overlay.board = self
        overlay.isUserInteractionEnabled = false
        addSubview(overlay)
        minimap.isUserInteractionEnabled = false
        minimap.isHidden = true
        addSubview(minimap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var scale: CGFloat { max(1, traitCollection.displayScale) }

    // MARK: Configuration

    func configure(_ session: ArrowJamSession, _ theme: ArrowTheme, _ showGrid: Bool, _ fitRequest: Int) {
        if self.session !== session {
            self.session = session
            // A new board (next level or retry) starts from the fitted camera, as Kotlin's reload().
            camera = ArrowCamera()
            didSetStart = false
            cameraAnimation = nil
            gesture = nil
            seenHintTick = 0
            seenBumpTick = 0
            seenWon = false
            scene = ArrowStaticScene(session.board, theme, showGrid)
            level = nil
            pendingLevel?.container.removeFromSuperlayer()
            pendingLevel = nil
            tileRoot.sublayers?.forEach { $0.removeFromSuperlayer() }
            minimap.reset()
            observe(session)
            setNeedsLayout()
        }
        if self.theme !== theme || self.showGrid != showGrid {
            self.theme = theme
            self.showGrid = showGrid
            scene.setLook(theme, showGrid)
            level?.invalidateAll()
            pendingLevel?.invalidateAll()
            minimap.theme = theme
        }
        if fitRequest != self.fitRequest {
            let fire = fitRequest > self.fitRequest
            self.fitRequest = fitRequest
            if fire && fitRequest > 0 { animateCamera(ArrowCamera(), 500) }
        }
        wake()
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { wake() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlay.frame = bounds
        minimap.frame = CGRect(x: bounds.width - 8 - 72, y: 8, width: 72, height: 72)
        // A new size changes the cell; the tiles stay up scaled until that zoom's tiles are drawn.
        if bounds.size != viewSize { viewSize = bounds.size }
        if let session, !didSetStart, viewSize.width > 0 {
            didSetStart = true
            let start = ArrowLayout(viewSize, session.level.w, session.level.h, ArrowCamera()).startZoom
            if start != camera.zoom { camera = ArrowCamera(start) }
        }
        frameUpdate()
    }

    /// Re-registers for the session properties that should wake the board.
    private func observe(_ session: ArrowJamSession) {
        observing = session
        withObservationTracking {
            _ = session.boardRevision
            _ = session.effects
            _ = session.hint?.first
            _ = session.aiming
            _ = session.inEntrance
            _ = session.phase
            _ = session.hintTick
            _ = session.bumpTick
            _ = session.replaying
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.observing === session else { return }
                self.observe(session)
                self.wake()
            }
        }
    }

    // MARK: Clock

    func wake() {
        guard window != nil else { return }
        if link == nil {
            let l = CADisplayLink(target: ArrowLinkProxy(self), selector: #selector(ArrowLinkProxy.tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            l.add(to: .main, forMode: .common)
            link = l
        }
        link?.isPaused = false
    }

    fileprivate func tick(_ link: CADisplayLink) {
        if !frameUpdate(link.targetTimestamp) { link.isPaused = true }
    }

    /// One frame: camera animation, session events, static-layer upkeep and the overlay. Returns
    /// whether another frame is needed soon.
    @discardableResult
    private func frameUpdate(_ timestamp: Double? = nil) -> Bool {
        guard let session, viewSize.width > 0, viewSize.height > 0 else { return false }
        let t = timestamp ?? nowSeconds()
        now = t
        var busy = false

        // Session events.
        if session.hintTick != seenHintTick {
            seenHintTick = session.hintTick
            if session.hintTick > 0 { reveal(session.hint?.first) }
        }
        if session.bumpTick != seenBumpTick {
            seenBumpTick = session.bumpTick
            if session.bumpTick > 0 { reveal(session.effects.last?.arrow) }
        }
        let won = session.phase == .Won
        if won != seenWon {
            seenWon = won
            if won { animateCamera(ArrowCamera(), 450) }
        }

        // Camera animation (Compose `animate(0f, 1f, tween(ms))`, FastOutSlowIn).
        if let a = cameraAnimation {
            let p = min(1, max(0, (t - a.start) / a.duration))
            let v = CGFloat(ArrowEase.fastOutSlowIn(p))
            camera = ArrowCamera(a.from.zoom + (a.to.zoom - a.from.zoom) * v, a.from.panX + (a.to.panX - a.from.panX) * v,
                                 a.from.panY + (a.to.panY - a.from.panY) * v)
            if p >= 1 { cameraAnimation = nil } else { busy = true }
        }

        let layout = currentLayout()
        let stable = cameraAnimation == nil && gesture?.mode != .pinch
        scene.update(session, t)
        if !scene.changed.isEmpty {
            level?.invalidate(scene.changed, scene)
            pendingLevel?.invalidate(scene.changed, scene)
            scene.changed.removeAll()
        }
        updateStaticLayer(layout, stable: stable)
        applyCameraTransform(layout)
        minimap.update(session, layout, camera.zoom > 1.05, scale)

        // Overlay: redraw while anything moves (and once more to clear it).
        let pending = level?.hasMissing ?? true
        let active = session.inEntrance || session.aiming != nil || (session.hint?.second ?? 0) > t
            || session.effects.contains { $0.isActive(t) } || pending
        if active || overlayWasActive { overlay.setNeedsDisplay() }
        overlayWasActive = active
        return busy || active || pendingLevel != nil || gesture != nil
    }

    private func currentLayout() -> ArrowLayout { layoutFor(camera) }

    private func layoutFor(_ c: ArrowCamera) -> ArrowLayout {
        ArrowLayout(viewSize, session?.level.w ?? 1, session?.level.h ?? 1, c)
    }

    /// Gestures only move the camera; the display link (running while a finger is down) redraws.
    fileprivate func setCamera(_ c: ArrowCamera) {
        camera = c
        wake()
    }

    private func animateCamera(_ target: ArrowCamera, _ ms: Double = 420) {
        cameraAnimation = (camera, target, nowSeconds(), ms / 1000)
        wake()
    }

    /// Eases the camera so `arrow` is on screen (after a hint or a bump).
    private func reveal(_ arrow: Int?) {
        guard let arrow, let session, viewSize != .zero, camera.zoom > 1.01, arrow >= 0, arrow < session.board.pieces.count else { return }
        let layout = layoutFor(camera)
        let piece = session.board.pieces[arrow]
        let center = layout.screen(ArrowGeometry.point(piece, Double(piece.cells.count - 1) / 2))
        let safe = CGRect(origin: .zero, size: viewSize).insetBy(dx: 50, dy: 50)
        if safe.contains(center) { return }
        animateCamera(layout.clamped(ArrowCamera(camera.zoom, camera.panX + viewSize.width / 2 - center.x, camera.panY + viewSize.height / 2 - center.y)))
    }

    // MARK: Static layer

    /// Keeps the tiles for the current zoom rendered and clean, within a per-frame time budget.
    private func updateStaticLayer(_ layout: ArrowLayout, stable: Bool) {
        let s = scale
        let cell = layout.cell
        if level == nil || level!.scale != s {
            level?.container.removeFromSuperlayer()
            pendingLevel?.container.removeFromSuperlayer()
            pendingLevel = nil
            level = ArrowTileLevel(cell: cell, scale: s)
            tileRoot.addSublayer(level!.container)
        } else if abs(level!.cell - cell) <= cell * 0.004 {
            pendingLevel?.container.removeFromSuperlayer()
            pendingLevel = nil
        } else if stable, pendingLevel.map({ abs($0.cell - cell) > cell * 0.004 }) ?? true {
            // The zoom settled somewhere new: render that zoom's tiles while the old ones stay up.
            pendingLevel?.container.removeFromSuperlayer()
            let p = ArrowTileLevel(cell: cell, scale: s)
            p.container.isHidden = true
            tileRoot.addSublayer(p.container)
            pendingLevel = p
        }
        guard let current = level else { return }
        let deadline = CACurrentMediaTime() + 0.005
        let visible = visibleTiles(current, layout)
        // Mid-pinch the tiles are scaled; far from their own zoom the overlay draws instead.
        let k = cell / current.cell
        if pendingLevel == nil && (stable || (k > 0.8 && k < 1.25)) { current.render(visible, scene, until: deadline) }
        if let p = pendingLevel {
            let wanted = visibleTiles(p, layout)
            p.render(wanted, scene, until: max(deadline, CACurrentMediaTime() + 0.001))
            if !p.missing(wanted) {
                current.container.removeFromSuperlayer()
                p.container.isHidden = false
                level = p
                pendingLevel = nil
                p.hasMissing = false
                p.evict(keeping: wanted)
                return
            }
        }
        current.evict(keeping: visible)
        current.hasMissing = current.missing(visible)
    }

    /// Tiles of `lvl` that overlap the view at the current camera.
    private func visibleTiles(_ lvl: ArrowTileLevel, _ layout: ArrowLayout) -> [ArrowTileKey] {
        let k = layout.cell / lvl.cell
        let origin = snapped(layout.origin)
        // View rect in the level's board-local points, limited to the board plus a one-cell margin.
        let x0 = max((0 - origin.x) / k, -lvl.cell)
        let y0 = max((0 - origin.y) / k, -lvl.cell)
        let x1 = min((viewSize.width - origin.x) / k, CGFloat(scene.w + 1) * lvl.cell)
        let y1 = min((viewSize.height - origin.y) / k, CGFloat(scene.h + 1) * lvl.cell)
        if x1 <= x0 || y1 <= y0 { return [] }
        let T = lvl.tileSize
        var out: [ArrowTileKey] = []
        for ty in Int((y0 / T).rounded(.down))...Int((y1 / T).rounded(.down)) {
            for tx in Int((x0 / T).rounded(.down))...Int((x1 / T).rounded(.down)) { out.append(ArrowTileKey(tx: tx, ty: ty)) }
        }
        return out
    }

    private func snapped(_ p: CGPoint) -> CGPoint {
        let s = scale
        return CGPoint(x: (p.x * s).rounded() / s, y: (p.y * s).rounded() / s)
    }

    private func applyCameraTransform(_ layout: ArrowLayout) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let o = snapped(layout.origin)
        for lvl in [level, pendingLevel].compactMap({ $0 }) {
            let k = layout.cell / lvl.cell
            lvl.container.setAffineTransform(CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: o.x, ty: o.y))
        }
        CATransaction.commit()
    }

    // MARK: Overlay drawing (Kotlin drawBoard, the parts that move)

    fileprivate func drawOverlay(_ ctx: CGContext) {
        guard let session, viewSize.width > 0 else { return }
        let t = now
        let layout = currentLayout()
        let o = snapped(layout.origin)
        let shift = CGPoint(x: o.x - layout.origin.x, y: o.y - layout.origin.y)
        ctx.translateBy(x: shift.x, y: shift.y)
        let board = session.board
        let cell = layout.cell
        let width = ArrowArt.bodyWidth(cell, theme)
        let glows = cell >= 6
        let tl = layout.cellSpace(CGPoint(x: -shift.x, y: -shift.y))
        let br = layout.cellSpace(CGPoint(x: viewSize.width - shift.x, y: viewSize.height - shift.y))
        let margin = 2 + width / cell
        func onScreen(_ id: Int) -> Bool {
            let b = scene.bounds[id]
            return CGFloat(b.maxC + 1) + margin >= tl.x && CGFloat(b.minC) - margin <= br.x
                && CGFloat(b.maxR + 1) + margin >= tl.y && CGFloat(b.minR) - margin <= br.y
        }

        // Tiles not rendered yet: draw their dots and resting arrows here, clipped to them.
        if let lvl = level, lvl.hasMissing {
            let rects = lvl.missingRects(visibleTiles(lvl, layout)).map { r -> CGRect in
                let k = cell / lvl.cell
                return CGRect(x: layout.origin.x + r.minX * k, y: layout.origin.y + r.minY * k, width: r.width * k, height: r.height * k)
            }
            if !rects.isEmpty {
                ctx.saveGState()
                ctx.clip(to: rects)
                let clip = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
                let ca = layout.cellSpace(CGPoint(x: clip.minX, y: clip.minY))
                let cb = layout.cellSpace(CGPoint(x: clip.maxX, y: clip.maxY))
                ArrowTileRenderer.draw(ctx, scene, cell: cell, origin: layout.origin, cellRect: CGRect(x: ca.x, y: ca.y, width: cb.x - ca.x, height: cb.y - ca.y))
                ctx.restoreGState()
            }
        }

        var busy = Set<Int>()
        for e in session.effects where e.hidesArrow && e.isActive(t) { busy.insert(e.arrow) }
        let hint = session.hint.flatMap { $0.second > t ? $0 : nil }
        let aiming = session.aiming
        func draw(_ piece: ArrowPiece, _ slide: Double, _ color: ArrowRGBA, _ glow: ArrowRGBA? = nil, _ opacity: CGFloat = 1, _ offset: CGPoint = .zero) {
            let points = ArrowGeometry.body(piece, slide).map { p -> CGPoint in
                let s = layout.screen(p)
                return CGPoint(x: s.x + offset.x, y: s.y + offset.y)
            }
            let dir = ArrowGeometry.direction(points, piece.heading)
            ArrowArt.drawArrow(ctx, points, dir, cell, ArrowArt.Style(color, width, theme.gloss, glows ? glow : nil, min(cell * 0.55, 9), opacity))
        }

        if session.inEntrance {
            // Opening fly-in: each arrow slides in from behind its tail with a springy settle.
            for piece in board.pieces {
                if !board.alive[piece.id] || busy.contains(piece.id) || !onScreen(piece.id) { continue }
                let p = min(max((t - session.entranceStart - session.entranceDelay(piece.id)) / 0.5, 0), 1)
                let settle = 1 - pow(2.0, -9 * p) * cos(p * 10.5)
                draw(piece, -(1 - settle) * 3, theme.color(piece.id), nil, CGFloat(min(1.0, p * 2.4)))
            }
        }

        for effect in session.effects {
            let p = effect.progress(t)
            if p >= 1 { continue }
            let piece = board.pieces[effect.arrow]
            let color = theme.color(piece.id)
            switch effect.kind {
            case let .Exit(travel):
                let slide = travel * pow(p, 1.7)
                let fade = CGFloat(p > 0.7 ? 1 - (p - 0.7) / 0.3 : 1)
                if !session.reduceMotion {
                    draw(piece, max(0, slide - 1.6 - p * 2), color, nil, 0.22 * fade)
                    draw(piece, max(0, slide - 3.2 - p * 4), color, nil, 0.1 * fade)
                }
                draw(piece, slide, color, color, fade)
            case let .Bump(distance):
                let d = Double(distance) + 0.35
                let slide: Double
                if p < 0.2 { slide = d * (1 - pow(1 - p / 0.2, 2)) } else if p < 0.5 { slide = d * (1 - (p - 0.2) / 0.3) * (1 - (p - 0.2) / 0.3) } else { slide = 0 }
                let shakeP = max(0.0, (p - 0.5) / 0.5)
                let perp = CGPoint(x: -piece.heading.dr, y: piece.heading.dc)
                let wobble = p > 0.5 && !session.reduceMotion ? CGFloat(sin(shakeP * 34)) * cell * 0.22 * CGFloat(1 - shakeP) : 0
                let red = p < 0.75
                draw(piece, session.reduceMotion ? 0 : slide, red ? ArrowTheme.crash : color, red ? ArrowTheme.crash : nil, 1,
                     CGPoint(x: perp.x * wobble, y: perp.y * wobble))
                if p > 0.16 && p < 0.5 {
                    let contact = layout.screen(ArrowGeometry.point(piece, Double(piece.cells.count - 1) + d + 0.2))
                    let spread = CGFloat((p - 0.16) / 0.34)
                    let crash = ArrowTheme.crash
                    ctx.saveGState()
                    ctx.setStrokeColor(red: crash.r, green: crash.g, blue: crash.b, alpha: 1 - spread)
                    ctx.setLineWidth(max(1.2, cell * 0.12))
                    ctx.setLineCap(.round)
                    for k in 0..<7 {
                        let angle = CGFloat(k) / 7 * 2 * .pi + 0.3
                        ctx.move(to: CGPoint(x: contact.x + cos(angle) * cell * (0.3 + spread * 0.6), y: contact.y + sin(angle) * cell * (0.3 + spread * 0.6)))
                        ctx.addLine(to: CGPoint(x: contact.x + cos(angle) * cell * (0.6 + spread * 1.1), y: contact.y + sin(angle) * cell * (0.6 + spread * 1.1)))
                    }
                    ctx.strokePath()
                    ctx.restoreGState()
                }
            case .Smash:
                let pf = CGFloat(p)
                if p < 0.25 {
                    let center = layout.screen(ArrowGeometry.point(piece, Double(piece.cells.count - 1) / 2))
                    let ring = cell * (1 + pf * 10)
                    ctx.saveGState()
                    ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.6 * (1 - pf / 0.25))
                    ctx.setLineWidth(max(2, cell * 0.25))
                    ctx.strokeEllipse(in: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2))
                    ctx.restoreGState()
                }
                ctx.saveGState()
                ctx.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: 1 - pf)
                for (k, c) in piece.cells.enumerated() {
                    for half in 0..<2 {
                        let seed = CGFloat((piece.id * 131 + k * 17 + half * 7) % 97) / 97
                        let angle = seed * 2 * .pi
                        let speed = cell * (2.5 + seed * 3)
                        let tt = pf * 0.75
                        let s0 = layout.screen(CGPoint(x: CGFloat(c.c) + 0.5, y: CGFloat(c.r) + 0.5))
                        let pos = CGPoint(x: s0.x + cos(angle) * speed * tt * 2, y: s0.y + sin(angle) * speed * tt * 2 + 900 * tt * tt)
                        let s = width * (1.1 + seed)
                        ctx.saveGState()
                        ctx.translateBy(x: pos.x, y: pos.y)
                        ctx.rotate(by: seed * 12 * pf + CGFloat(half))
                        ctx.addPath(CGPath(roundedRect: CGRect(x: -s / 2, y: -s / 3, width: s, height: s * 0.66), cornerWidth: s * 0.15, cornerHeight: s * 0.15, transform: nil))
                        ctx.fillPath()
                        ctx.restoreGState()
                    }
                }
                ctx.restoreGState()
            case .Lane:
                let head = layout.screen(ArrowGeometry.point(piece, Double(piece.cells.count - 1)))
                ArrowArt.drawLane(ctx, head, CGPoint(x: piece.heading.dc, y: piece.heading.dr), CGFloat(board.laneLength(piece.id) + 2) * cell, cell,
                                  ArrowTheme.hint.copy(alpha: 1 - CGFloat(p)))
            }
        }

        // Hint: the arrow pulses green with its lane drawn to the edge.
        if let hint, board.alive[hint.first], aiming != hint.first {
            let piece = board.pieces[hint.first]
            let pulse = CGFloat(0.5 + 0.5 * sin(t * 7))
            let head = layout.screen(ArrowGeometry.point(piece, Double(piece.cells.count - 1)))
            ArrowArt.drawLane(ctx, head, CGPoint(x: piece.heading.dc, y: piece.heading.dr), CGFloat(board.laneLength(piece.id) + 2) * cell, cell,
                              ArrowTheme.hint.copy(alpha: 0.55 + 0.4 * pulse))
            draw(piece, 0, ArrowTheme.hint, ArrowTheme.hint.copy(alpha: 0.5 + 0.5 * pulse))
        }

        // Hold to aim: the arrow lifts and previews its lane, green if clear, red up to the blocker.
        if let aiming, aiming >= 0, aiming < board.pieces.count, board.alive[aiming] {
            let piece = board.pieces[aiming]
            let blocker = board.blocker(aiming)
            let head = layout.screen(ArrowGeometry.point(piece, Double(piece.cells.count - 1)))
            let dir = CGPoint(x: piece.heading.dc, y: piece.heading.dr)
            let laneColor = blocker == nil ? ArrowTheme.hint : ArrowTheme.crash
            let length = CGFloat(blocker.map { $0.second + 1 } ?? (board.laneLength(aiming) + 2)) * cell
            ArrowArt.drawLane(ctx, head, dir, length, cell, laneColor)
            if blocker != nil {
                let x = CGPoint(x: head.x + dir.x * length, y: head.y + dir.y * length)
                let s = max(4, cell * 0.35)
                let c = ArrowTheme.crash
                ctx.saveGState()
                ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
                ctx.setLineWidth(max(2, cell * 0.18))
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: x.x - s, y: x.y - s))
                ctx.addLine(to: CGPoint(x: x.x + s, y: x.y + s))
                ctx.move(to: CGPoint(x: x.x + s, y: x.y - s))
                ctx.addLine(to: CGPoint(x: x.x - s, y: x.y + s))
                ctx.strokePath()
                ctx.restoreGState()
            }
            draw(piece, 0.12, theme.color(aiming), laneColor)
        }
    }

    // MARK: Touches (Kotlin awaitEachGesture state machine)

    /// The arrow under `location`, with a forgiving radius on dense boards.
    private func hit(_ location: CGPoint, _ layout: ArrowLayout) -> Int? {
        guard let board = session?.board else { return nil }
        let p = layout.cellSpace(location)
        let radius = max(1.2, 14 / layout.cell)
        var best: (id: Int, d: CGFloat, hd: CGFloat)?
        let r0 = Int((p.y - radius).rounded(.down)), r1 = Int((p.y + radius).rounded(.up))
        let c0 = Int((p.x - radius).rounded(.down)), c1 = Int((p.x + radius).rounded(.up))
        for r in r0...r1 {
            for c in c0...c1 {
                guard let id = board.piece(ArrowCell(r, c)) else { continue }
                let distance = hypot(p.x - (CGFloat(c) + 0.5), p.y - (CGFloat(r) + 0.5))
                if distance > radius { continue }
                let head = board.pieces[id].head
                let hd = hypot(p.x - (CGFloat(head.c) + 0.5), p.y - (CGFloat(head.r) + 0.5))
                if let cur = best {
                    if distance < cur.d - 0.01 || (abs(distance - cur.d) <= 0.01 && hd < cur.hd) { best = (id, distance, hd) }
                } else {
                    best = (id, distance, hd)
                }
            }
        }
        return best?.id
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session != nil else { return }
        if gesture == nil {
            guard let first = touches.first else { return }
            cameraAnimation = nil
            let g = ArrowGesture(down: first, start: first.location(in: self), base: camera, layout0: layoutFor(camera))
            gesture = g
            g.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in self?.holdTimedOut() }
        }
        guard let g = gesture else { return }
        for t in touches where !g.pressed.contains(t) { g.pressed.append(t) }
        if g.pressed.count >= 2 {
            switch g.mode {
            case .undecided, .pan:
                g.cancelTimer()
                g.mode = .pinch
            case .aim:
                g.cancelled = true
                session?.setAim(nil)
                g.mode = .pinch
            case .pinch:
                break
            }
            pinchMoved(g)
        }
        wake()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let g = gesture, let session else { return }
        switch g.mode {
        case .undecided:
            let ch = g.pressed.contains(g.down) ? g.down : g.pressed.first
            if let ch, distance(ch.location(in: self), g.start) > 10 {
                g.cancelTimer()
                g.mode = .pan
                panMoved(g)
            }
        case .aim:
            if !g.cancelled, let ch = g.pressed.first, distance(ch.location(in: self), g.start) > 24 {
                g.cancelled = true
                session.setAim(nil)
            }
        case .pan:
            panMoved(g)
        case .pinch:
            pinchMoved(g)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lifted(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lifted(touches, cancelled: true) }

    private func lifted(_ touches: Set<UITouch>, cancelled: Bool) {
        guard let g = gesture, let session else { return }
        g.pressed.removeAll { touches.contains($0) }
        if !g.pressed.isEmpty { return }
        g.cancelTimer()
        gesture = nil
        switch g.mode {
        case .undecided:
            if !cancelled, let id = hit(g.start, g.layout0) { session.fire(id) }
        case .aim:
            let aimed = session.aiming
            session.setAim(nil)
            if !g.cancelled && !cancelled, let aimed { session.fire(aimed) }
        case .pan:
            break
        case .pinch:
            if camera.zoom < 1.04 { animateCamera(ArrowCamera(), 250) }
        }
        wake()
    }

    private func holdTimedOut() {
        guard let g = gesture, g.mode == .undecided, let session else { return }
        // Aim: lift the arrow and preview its lane; release fires, sliding away cancels.
        g.mode = .aim
        let arrow = hit(g.start, g.layout0)
        if let arrow {
            session.setAim(arrow)
            Haptics.selection()
        }
        g.cancelled = arrow == nil
        wake()
    }

    private func panMoved(_ g: ArrowGesture) {
        guard let ch = g.pressed.first else { return }
        let p = ch.location(in: self)
        setCamera(layoutFor(camera).clamped(ArrowCamera(camera.zoom, g.base.panX + p.x - g.start.x, g.base.panY + p.y - g.start.y)))
    }

    private func pinchMoved(_ g: ArrowGesture) {
        guard g.pressed.count >= 2 else { return }
        let a = g.pressed[0].location(in: self)
        let b = g.pressed[1].location(in: self)
        let dist = distance(a, b)
        if g.pinchBase == nil {
            g.pinchBase = camera
            g.startDistance = max(1, dist)
            g.anchor = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        let pb = g.pinchBase!
        let layout = layoutFor(pb)
        let zoom = min(max(pb.zoom * dist / g.startDistance, 1), layout.maxZoom)
        let k = zoom / pb.zoom
        let ax = g.anchor.x - viewSize.width / 2
        let ay = g.anchor.y - viewSize.height / 2
        setCamera(layout.clamped(ArrowCamera(zoom, ax - (ax - pb.panX) * k, ay - (ay - pb.panY) * k)))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

/// One finger-down-to-all-up interaction on the board.
private final class ArrowGesture {
    enum Mode { case undecided, pan, pinch, aim }

    let down: UITouch
    let start: CGPoint
    let base: ArrowCamera
    let layout0: ArrowLayout
    var pressed: [UITouch] = []
    var mode = Mode.undecided
    var cancelled = false
    var timer: Timer?
    var pinchBase: ArrowCamera?
    var startDistance: CGFloat = 1
    var anchor = CGPoint.zero

    init(down: UITouch, start: CGPoint, base: ArrowCamera, layout0: ArrowLayout) {
        self.down = down
        self.start = start
        self.base = base
        self.layout0 = layout0
    }

    func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }
}

private final class ArrowLinkProxy: NSObject {
    weak var owner: ArrowBoardUIView?
    init(_ o: ArrowBoardUIView) { owner = o }
    @objc func tick(_ link: CADisplayLink) {
        guard let owner else { link.invalidate(); return }
        owner.tick(link)
    }
}

/// Compose's `FastOutSlowInEasing` = cubic-bezier(0.4, 0, 0.2, 1).
enum ArrowEase {
    static func fastOutSlowIn(_ x: Double) -> Double { cubicBezier(x, 0.4, 0, 0.2, 1) }

    static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bx(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t }
        func by(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            let v = bx(t)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return by(t)
    }
}

// MARK: - Overlay and minimap

final class ArrowOverlayView: UIView {
    weak var board: ArrowBoardUIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        board?.drawOverlay(ctx)
    }
}

/// The 72-point overview in the corner while zoomed in: live arrows plus the visible area.
final class ArrowMinimapView: UIView {
    var theme = ArrowTheme.night {
        didSet { if theme !== oldValue { cellsRevision = -1; applyLook() } }
    }

    private let cells = CALayer()
    private let viewport = CAShapeLayer()
    private var cellsRevision = -1
    private weak var cellsBoard: ArrowBoard?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        clipsToBounds = true
        cells.actions = ArrowTileLevel.noActions
        viewport.actions = ArrowTileLevel.noActions
        viewport.fillColor = nil
        viewport.lineWidth = 2
        layer.addSublayer(cells)
        layer.addSublayer(viewport)
        applyLook()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyLook() {
        backgroundColor = UIColor(cgColor: theme.glass.cg)
        layer.borderColor = theme.stroke.cg
        viewport.strokeColor = ArrowTheme.hint.cg
    }

    func reset() {
        cellsRevision = -1
        cellsBoard = nil
        isHidden = true
    }

    @MainActor
    func update(_ session: ArrowJamSession, _ layout: ArrowLayout, _ zoomed: Bool, _ scale: CGFloat) {
        if isHidden == zoomed { isHidden = !zoomed }
        if !zoomed { return }
        let size = bounds.size
        let k = min((size.width - 8) / CGFloat(layout.width), (size.height - 8) / CGFloat(layout.height))
        let ox = (size.width - CGFloat(layout.width) * k) / 2
        let oy = (size.height - CGFloat(layout.height) * k) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if cellsRevision != session.boardRevision || cellsBoard !== session.board {
            cellsRevision = session.boardRevision
            cellsBoard = session.board
            cells.frame = bounds
            cells.contentsScale = scale
            cells.contents = renderCells(session.board, size, k, ox, oy, scale)
        }
        let tl = layout.cellSpace(.zero)
        let br = layout.cellSpace(CGPoint(x: layout.size.width, y: layout.size.height))
        let view = CGRect(x: ox + tl.x * k, y: oy + tl.y * k, width: (br.x - tl.x) * k, height: (br.y - tl.y) * k)
            .intersection(CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
        viewport.frame = bounds
        viewport.path = view.isNull ? nil : CGPath(roundedRect: view, cornerWidth: 3, cornerHeight: 3, transform: nil)
        CATransaction.commit()
    }

    /// The live arrows' cells (Kotlin `minimapCells`), drawn once per board change.
    private func renderCells(_ board: ArrowBoard, _ size: CGSize, _ k: CGFloat, _ ox: CGFloat, _ oy: CGFloat, _ scale: CGFloat) -> CGImage? {
        let pw = Int((size.width * scale).rounded(.up)), ph = Int((size.height * scale).rounded(.up))
        guard pw > 0, ph > 0, let ctx = ArrowTileRenderer.context(pw, ph) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        let c = theme.hud.copy(alpha: 0.45)
        ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        let path = CGMutablePath()
        for piece in board.pieces where board.alive[piece.id] {
            for cell in piece.cells {
                path.addRect(CGRect(x: ox + CGFloat(cell.c) * k, y: oy + CGFloat(cell.r) * k, width: k, height: k))
            }
        }
        ctx.addPath(path)
        ctx.fillPath()
        return ctx.makeImage()
    }
}

// MARK: - Static layer: scene, tiles, rendering

/// What the cached layer shows: dots, and every arrow at rest (not moving, hinted or aimed).
struct ArrowStaticScene {
    struct Box { let minR: Int; let maxR: Int; let minC: Int; let maxC: Int }

    private(set) var pieces: [ArrowPiece] = []
    private(set) var bounds: [Box] = []
    /// Rest points of each arrow in cell units, and its head direction.
    private(set) var rest: [[CGPoint]] = []
    private(set) var restDirection: [CGPoint] = []
    private(set) var drawn: [Bool] = []
    private(set) var dead: [Bool] = []
    private(set) var theme = ArrowTheme.night
    private(set) var grid = false
    private(set) var w = 1
    private(set) var h = 1
    private weak var board: ArrowBoard?
    private var revision = -1
    /// Arrows whose look changed since the tiles were drawn (to invalidate their tiles).
    var changed: [Int] = []

    init() {}

    init(_ board: ArrowBoard, _ theme: ArrowTheme, _ grid: Bool) {
        self.board = board
        pieces = board.pieces
        w = board.width
        h = board.height
        self.theme = theme
        self.grid = grid
        bounds = pieces.map { p in
            var minR = Int.max, maxR = Int.min, minC = Int.max, maxC = Int.min
            for c in p.cells {
                minR = min(minR, c.r); maxR = max(maxR, c.r)
                minC = min(minC, c.c); maxC = max(maxC, c.c)
            }
            return Box(minR: minR, maxR: maxR, minC: minC, maxC: maxC)
        }
        rest = pieces.map { ArrowGeometry.body($0, 0) }
        restDirection = pieces.indices.map { ArrowGeometry.direction(rest[$0], pieces[$0].heading) }
        drawn = [Bool](repeating: false, count: pieces.count)
        dead = [Bool](repeating: false, count: pieces.count)
    }

    mutating func setLook(_ theme: ArrowTheme, _ grid: Bool) {
        self.theme = theme
        self.grid = grid
    }

    /// Recomputes which arrows rest and which left; records the ones that changed.
    @MainActor
    mutating func update(_ session: ArrowJamSession, _ t: Double) {
        if board !== session.board {
            // Replay swaps in a fresh board with the same pieces.
            board = session.board
            revision = -1
        }
        let b = session.board
        var excluded: Set<Int> = []
        if !session.inEntrance {
            for e in session.effects where e.hidesArrow && e.isActive(t) { excluded.insert(e.arrow) }
            if let hint = session.hint, hint.second > t { excluded.insert(hint.first) }
            if let a = session.aiming { excluded.insert(a) }
        }
        for i in pieces.indices {
            let isDead = !b.alive[i]
            let isDrawn = !isDead && !session.inEntrance && !excluded.contains(i)
            if isDead != dead[i] || isDrawn != drawn[i] {
                dead[i] = isDead
                drawn[i] = isDrawn
                changed.append(i)
            }
        }
        revision = session.boardRevision
    }
}

struct ArrowTileKey: Hashable {
    let tx: Int
    let ty: Int
}

/// The tiles for one zoom (cell size): 256-pixel CGImages in board-local points.
final class ArrowTileLevel {
    static let tilePx = 256
    static let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "transform": NSNull(),
                                                 "hidden": NSNull(), "sublayers": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull(), "frame": NSNull()]

    private final class Tile {
        let layer = CALayer()
        var clean = false
        var lastUsed = 0
    }

    let cell: CGFloat
    let scale: CGFloat
    let container = CALayer()
    var hasMissing = true
    private var tiles: [ArrowTileKey: Tile] = [:]
    private var frameCounter = 0

    var tileSize: CGFloat { CGFloat(ArrowTileLevel.tilePx) / scale }

    init(cell: CGFloat, scale: CGFloat) {
        self.cell = cell
        self.scale = scale
        container.anchorPoint = .zero
        container.actions = ArrowTileLevel.noActions
    }

    func rect(_ key: ArrowTileKey) -> CGRect {
        let T = tileSize
        return CGRect(x: CGFloat(key.tx) * T, y: CGFloat(key.ty) * T, width: T, height: T)
    }

    func invalidateAll() {
        for t in tiles.values { t.clean = false; t.layer.contents = nil }
    }

    /// Drops the tiles under arrows that changed (their area is drawn by the overlay until re-rendered).
    func invalidate(_ arrows: [Int], _ scene: ArrowStaticScene) {
        if arrows.isEmpty || tiles.isEmpty { return }
        let T = tileSize
        for id in arrows {
            let b = scene.bounds[id]
            let x0 = (CGFloat(b.minC) - 1) * cell, x1 = (CGFloat(b.maxC) + 2) * cell
            let y0 = (CGFloat(b.minR) - 1) * cell, y1 = (CGFloat(b.maxR) + 2) * cell
            for ty in Int((y0 / T).rounded(.down))...Int((y1 / T).rounded(.down)) {
                for tx in Int((x0 / T).rounded(.down))...Int((x1 / T).rounded(.down)) {
                    if let t = tiles[ArrowTileKey(tx: tx, ty: ty)], t.clean {
                        t.clean = false
                        t.layer.contents = nil
                    }
                }
            }
        }
    }

    func missing(_ keys: [ArrowTileKey]) -> Bool { keys.contains { tiles[$0]?.clean != true } }

    func missingRects(_ keys: [ArrowTileKey]) -> [CGRect] { keys.filter { tiles[$0]?.clean != true }.map(rect) }

    /// Renders missing tiles among `keys` until `deadline` (at least one per call).
    func render(_ keys: [ArrowTileKey], _ scene: ArrowStaticScene, until deadline: CFTimeInterval) {
        frameCounter += 1
        var first = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for key in keys {
            let tile: Tile
            if let t = tiles[key] {
                tile = t
            } else {
                tile = Tile()
                tile.layer.actions = ArrowTileLevel.noActions
                tile.layer.anchorPoint = .zero
                tile.layer.frame = rect(key)
                tile.layer.contentsScale = scale
                tile.layer.isOpaque = false
                tiles[key] = tile
                container.addSublayer(tile.layer)
            }
            tile.lastUsed = frameCounter
            if tile.clean { continue }
            if !first && CACurrentMediaTime() > deadline { continue }
            first = false
            tile.layer.contents = ArrowTileRenderer.renderTile(scene, cell: cell, scale: scale, rect: rect(key))
            tile.clean = true
        }
        CATransaction.commit()
    }

    /// Frees tiles that are off screen once there are many.
    func evict(keeping keys: [ArrowTileKey]) {
        guard tiles.count > 160 else { return }
        let keep = Set(keys)
        let victims = tiles.filter { !keep.contains($0.key) }.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (key, tile) in victims.prefix(tiles.count - 120) {
            tile.layer.removeFromSuperlayer()
            tiles[key] = nil
        }
    }
}

enum ArrowTileRenderer {
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// One tile: the board-local `rect` (points) at `scale` pixels per point. Nil when empty.
    static func renderTile(_ scene: ArrowStaticScene, cell: CGFloat, scale: CGFloat, rect: CGRect) -> CGImage? {
        let cellRect = CGRect(x: rect.minX / cell, y: rect.minY / cell, width: rect.width / cell, height: rect.height / cell)
        if !hasContent(scene, cellRect) { return nil }
        let px = ArrowTileLevel.tilePx
        guard let ctx = context(px, px) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(px))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        draw(ctx, scene, cell: cell, origin: .zero, cellRect: cellRect, shadowScale: scale)
        return ctx.makeImage()
    }

    private static func hasContent(_ scene: ArrowStaticScene, _ r: CGRect) -> Bool {
        if scene.grid {
            let c0 = max(0, Int((r.minX - 1).rounded(.down))), c1 = min(scene.w - 1, Int((r.maxX + 1).rounded(.up)))
            let r0 = max(0, Int((r.minY - 1).rounded(.down))), r1 = min(scene.h - 1, Int((r.maxY + 1).rounded(.up)))
            if c0 <= c1 && r0 <= r1 { return true }
        }
        for i in scene.pieces.indices where scene.drawn[i] || scene.dead[i] {
            if intersects(scene.bounds[i], r) { return true }
        }
        return false
    }

    @inline(__always)
    private static func intersects(_ b: ArrowStaticScene.Box, _ r: CGRect) -> Bool {
        CGFloat(b.maxC + 2) >= r.minX && CGFloat(b.minC - 1) <= r.maxX && CGFloat(b.maxR + 2) >= r.minY && CGFloat(b.minR - 1) <= r.maxY
    }

    /// Dots (the grid and where arrows used to be) and resting arrows inside `cellRect`, for a board
    /// whose cell (0, 0) corner is at `origin` with `cell`-point cells.
    static func draw(_ ctx: CGContext, _ scene: ArrowStaticScene, cell: CGFloat, origin: CGPoint, cellRect r: CGRect, shadowScale: CGFloat = 1) {
        let theme = scene.theme
        let dot = min(max(1.4, cell * 0.16), 4.5)
        let radius = dot / 2
        func center(_ row: Int, _ col: Int) -> CGPoint { CGPoint(x: origin.x + (CGFloat(col) + 0.5) * cell, y: origin.y + (CGFloat(row) + 0.5) * cell) }
        if scene.grid {
            let c0 = max(0, Int((r.minX - 1).rounded(.down))), c1 = min(scene.w - 1, Int((r.maxX + 1).rounded(.up)))
            let r0 = max(0, Int((r.minY - 1).rounded(.down))), r1 = min(scene.h - 1, Int((r.maxY + 1).rounded(.up)))
            if c0 <= c1 && r0 <= r1 {
                let d = theme.dots
                ctx.setFillColor(red: d.r, green: d.g, blue: d.b, alpha: d.a * 0.7)
                for row in r0...r1 { for col in c0...c1 { ArrowArt.fillCircle(ctx, center(row, col), radius) } }
            }
        }
        let d = theme.dots
        ctx.setFillColor(red: d.r, green: d.g, blue: d.b, alpha: d.a)
        for i in scene.pieces.indices where scene.dead[i] && intersects(scene.bounds[i], r) {
            for c in scene.pieces[i].cells { ArrowArt.fillCircle(ctx, center(c.r, c.c), radius) }
        }
        let width = ArrowArt.bodyWidth(cell, theme)
        for i in scene.pieces.indices where scene.drawn[i] && intersects(scene.bounds[i], r) {
            let points = scene.rest[i].map { CGPoint(x: origin.x + $0.x * cell, y: origin.y + $0.y * cell) }
            ArrowArt.drawArrow(ctx, points, scene.restDirection[i], cell, ArrowArt.Style(theme.color(i), width, theme.gloss, nil, min(cell * 0.55, 9), 1),
                               shadowScale: shadowScale)
        }
    }
}
