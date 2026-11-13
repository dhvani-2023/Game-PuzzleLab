import SwiftUI
import Observation
import GameKit

// MARK: - Tweens

enum Ease { case Linear, In, Out, InOut }

@inline(__always)
private func ease(_ e: Ease, _ x: CGFloat) -> CGFloat {
    switch e {
    case .Linear: return x
    case .In: return x * x
    case .Out: return 1 - (1 - x) * (1 - x)
    case .InOut: return x < 0.5 ? 2 * x * x : 1 - (-2 * x + 2) * (-2 * x + 2) / 2
    }
}

@inline(__always)
private func clamp01(_ x: CGFloat) -> CGFloat { x < 0 ? 0 : (x > 1 ? 1 : x) }

/** One animated number: a queue of timed segments, like a sequence of SpriteKit actions. */
final class Track {
    private struct Seg {
        let t0: CGFloat
        let t1: CGFloat
        let from: CGFloat
        let to: CGFloat
        let ease: Ease
    }

    private var base: CGFloat
    private var segs: [Seg] = []
    private var cursor: CGFloat = 0

    init(_ initial: CGFloat) {
        base = initial
        segs.reserveCapacity(4)
    }

    func value(_ t: CGFloat) -> CGFloat {
        var v = base
        for s in segs {
            if t < s.t0 { return v }
            if t >= s.t1 { v = s.to; continue }
            let x = clamp01((t - s.t0) / (s.t1 - s.t0))
            return s.from + (s.to - s.from) * ease(s.ease, x)
        }
        return v
    }

    /** Drops any running animation and holds `v`. */
    @discardableResult
    func set(_ t: CGFloat, _ v: CGFloat) -> Track {
        base = v
        segs.removeAll(keepingCapacity: true)
        cursor = t
        return self
    }

    /** Starts a new sequence at `t` from wherever the value is now. */
    @discardableResult
    func start(_ t: CGFloat) -> Track { set(t, value(t)) }

    @discardableResult
    func to(_ target: CGFloat, _ duration: CGFloat, _ e: Ease = .Linear) -> Track {
        let from = segs.last?.to ?? base
        segs.append(Seg(t0: cursor, t1: cursor + max(duration, 0.0001), from: from, to: target, ease: e))
        cursor += duration
        return self
    }

    @discardableResult
    func wait(_ duration: CGFloat) -> Track {
        cursor += duration
        return self
    }

    var end: CGFloat { cursor }
}

/** A tray piece on screen. */
final class TrayNode {
    let piece: TilePiece
    let x: Track
    let y: Track
    let scale: Track
    let alpha = Track(1)
    var gone = false

    init(_ piece: TilePiece, _ x: CGFloat, _ y: CGFloat, _ scale: CGFloat) {
        self.piece = piece
        self.x = Track(x)
        self.y = Track(y)
        self.scale = Track(scale)
    }
}

/** A short-lived effect, drawn until `end`. */
class Fx {
    let start: CGFloat
    let end: CGFloat

    init(_ start: CGFloat, end: CGFloat) {
        self.start = start
        self.end = end
    }

    func draw(_ ctx: GraphicsContext, _ s: TileScene, _ t: CGFloat) {}
}

extension GraphicsContext {
    /** Draws a bitmap centred at `c`, `w`×`h` px, scaled and rotated about its centre (pixel-snapped like Android). */
    func sprite(_ image: TileSprite, _ c: CGPoint, _ w: CGFloat, _ h: CGFloat, _ alpha: CGFloat = 1, _ rotation: CGFloat = 0,
                blend: GraphicsContext.BlendMode = .normal) {
        if alpha <= 0.003 || w <= 0.5 || h <= 0.5 { return }
        let rect = CGRect(x: (c.x - w / 2).rounded(), y: (c.y - h / 2).rounded(), width: w.rounded(), height: h.rounded())
        if alpha >= 1 && rotation == 0 && blend == .normal {
            draw(image.image, in: rect)
            return
        }
        var g = self
        if alpha < 1 { g.opacity = Double(alpha) }
        if blend != .normal { g.blendMode = blend }
        if rotation != 0 {
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(Double(rotation)))
            g.translateBy(x: -c.x, y: -c.y)
        }
        g.draw(image.image, in: rect)
    }

    /// Kotlin `drawLabel`: the outline layout, then the fill layout, both centred on `c`.
    func label(_ l: TileLabel, _ c: CGPoint, _ alpha: CGFloat) {
        let a = clamp01(alpha)
        if a <= 0.003 { return }
        let rect = CGRect(x: c.x - l.width / 2 - l.pad, y: c.y - l.height / 2 - l.pad, width: l.width + l.pad * 2, height: l.height + l.pad * 2)
        var g = self
        if a < 1 { g.opacity = Double(a) }
        g.draw(l.outline.image, in: rect)
        g.draw(l.inner.image, in: rect)
    }
}

/// The scene's redraw counter (the only observed state, so SwiftUI redraws the canvas once per tick).
@Observable
final class TileSceneClock {
    var frame = 0
}

/**
 * Draws a `TileBoard` and the tray, handles drag and drop, and animates every placement: ghost
 * preview, clear glow, clear wave, beams, praise, combo, fever, gems and game over. A port of the
 * Android `TileScene` (itself a port of the iOS SpriteKit `TileBurstScene`), driven by a display link.
 * Everything is in pixels with `density` = the screen scale, exactly like the Android code.
 */
final class TileScene {
    static let HINT_LOOP: CGFloat = 1.85

    unowned let session: TileBurstSession
    let board: TileBoard
    let reduceMotion: Bool

    /** Bumped every frame something can move, to redraw the canvas. */
    let clock = TileSceneClock()
    var frame: Int { clock.frame }
    private(set) var time: CGFloat = 0

    // Layout (px)
    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 0
    private(set) var density: CGFloat = 1
    private(set) var cell: CGFloat = 40
    private(set) var cellPx = 40
    private(set) var origin: CGPoint = .zero
    private(set) var boardWidth: CGFloat = 320
    private(set) var margin: CGFloat = 12
    private(set) var trayY: CGFloat = 0
    private(set) var slotX: [CGFloat] = [0, 0, 0]
    private(set) var trayScale: CGFloat = 0.5
    private var laidOut = false

    /** HUD goal chip centres (global points, as SwiftUI reports them), for flying gems. */
    private(set) var goalTargets: [Int: CGPoint] = [:]
    /// Where the scene's canvas sits on screen (global points), to map HUD positions into scene pixels.
    var globalOrigin: CGPoint = .zero

    func setGoalTarget(_ index: Int, _ global: CGPoint) { goalTargets[index] = global }

    /// A HUD position (global points) in scene pixels.
    private func scenePoint(_ global: CGPoint) -> CGPoint {
        CGPoint(x: (global.x - globalOrigin.x) * density, y: (global.y - globalOrigin.y) * density)
    }

    // Sprites for the current cell size (looked up once per layout, never per frame).
    private(set) var backgroundSprite: TileSprite?
    private var blockSprites: [TileSprite] = []
    private var gemSprites: [TileSprite] = []
    private var outlineSprite: TileSprite!
    private var boardSprite: TileSprite!
    private var feverBoardSprite: TileSprite!
    private var flashSquare: TileSprite!
    private var greySquare: TileSprite!
    private var lineGlowSprites: [TileSprite] = []
    private var shardSprites: [TileSprite] = []
    private var beamSprites: [TileSprite] = []
    private var feverGlow: TileSprite!
    private var shelf = Path()
    private var shelfStroke = StrokeStyle(lineWidth: 1.5)

    // State
    var tray: [TrayNode?] = [nil, nil, nil]
    private let blockScale = (0..<64).map { _ in Track(1) }
    private let grey = (0..<64).map { _ in Track(0) }
    /** Removed blocks still drawn until their burst (revive). */
    private var lingering: [(block: TileBlock, until: CGFloat)?] = Array(repeating: nil, count: 64)
    private var fx: [Fx] = []
    private var timers: [(at: CGFloat, run: () -> Void)] = []
    private let shakeX = Track(0)
    private let shakeY = Track(0)
    private let feverAlpha = Track(0)
    private var feverSince: CGFloat?
    private var feverFadeOut: CGFloat?
    private(set) var greyed = false
    private let trayAlpha = Track(1)

    // Input
    private(set) var busy = false
    private var drag: (slot: Int, node: TrayNode)?
    private var snapped: Int?
    private var tinted: UInt64 = 0
    private var tintTone = 0
    private var glowRows: [Int] = []
    private var glowCols: [Int] = []
    private var glowSince: CGFloat = 0
    private var idle: CGFloat = 0
    private var hint: (slot: Int, origin: Int, since: CGFloat)?
    /// True between a touch-down and its release (the canvas gesture uses it to call `began` once).
    var touchActive = false

    init(_ session: TileBurstSession, _ board: TileBoard, _ reduceMotion: Bool) {
        self.session = session
        self.board = board
        self.reduceMotion = reduceMotion
    }

    // MARK: Layout

    func layout(_ w: CGFloat, _ h: CGFloat, _ topInset: CGFloat, _ bottomInset: CGFloat, _ density: CGFloat) {
        if laidOut && w == width && h == height { return }
        width = w
        height = h
        self.density = density
        let available = h - topInset - bottomInset
        cell = floor(min((w - 36 * density) / 8, available / (8 + 0.7 + 3.1), 56 * density))
        cellPx = Kt.roundToInt(Double(cell))
        boardWidth = cell * 8
        margin = CGFloat(TileArt.boardMargin(Float(cell)))
        let group = boardWidth + margin * 2 + cell * 3.1
        let top = topInset + max(0, available - group) * 0.35
        origin = CGPoint(x: CGFloat(Kt.roundToInt(Double((w - boardWidth) / 2))), y: CGFloat(Kt.roundToInt(Double(top + margin))))
        trayY = origin.y + boardWidth + margin + cell * 1.65
        slotX = [w / 2 - boardWidth / 3, w / 2, w / 2 + boardWidth / 3]
        trayScale = min(0.56, (boardWidth / 3 - 8 * density) / 5 / cell)
        if !laidOut {
            for (k, piece) in session.tray.enumerated() { tray[k] = piece.map { TrayNode($0, slotX[k], trayY, trayScale) } }
        } else {
            for (k, node) in tray.enumerated() {
                guard let node else { continue }
                node.x.set(time, slotX[k])
                node.y.set(time, trayY)
                node.scale.set(time, trayScale)
            }
        }
        loadSprites(Int(w.rounded()), Int(h.rounded()))
        laidOut = true
        if board.fever { startFever(false) }
    }

    private func loadSprites(_ w: Int, _ h: Int) {
        TileArt.warmUp(cellPx)
        backgroundSprite = TileArt.background(session.world, w, h, Float(density))
        blockSprites = (0..<TileArt.tones.count).map { TileArt.block($0, cellPx) }
        gemSprites = TileGem.allCases.map { TileArt.gem($0, cellPx) }
        outlineSprite = TileArt.outline(cellPx)
        boardSprite = TileArt.board(cellPx, false)
        feverBoardSprite = TileArt.board(cellPx, true)
        flashSquare = TileArt.roundSquare(cellPx, 0xFFFFFF)
        greySquare = TileArt.roundSquare(cellPx, 0x6B6F8A)
        lineGlowSprites = (0..<TileArt.tones.count).map { TileArt.tint("lineGlow", TileArt.lineGlow, TileArt.color(TileArt.tones[$0]).mix(.white, 0.35)) }
        shardSprites = (0..<TileArt.tones.count).map { TileArt.tint("shard", TileArt.shard, TileArt.color(TileArt.tones[$0]).mix(.white, 0.15)) }
        beamSprites = (0..<TileArt.tones.count).map { TileArt.tint("beam", TileArt.beam, TileArt.color(TileArt.tones[$0])) }
        feverGlow = TileArt.tint("glow", TileArt.glow, TileArt.color(0xFFB020))
        let shelfW = boardWidth + margin * 2
        let shelfH = cell * 2.9
        shelf = Path(roundedRect: CGRect(x: width / 2 - shelfW / 2, y: trayY - shelfH / 2, width: shelfW, height: shelfH), cornerRadius: cell * 0.6)
        shelfStroke = StrokeStyle(lineWidth: 1.5 * density)
    }

    @inline(__always)
    func point(_ i: Int) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(TileGrid.col(i)) + 0.5) * cell, y: origin.y + (CGFloat(TileGrid.row(i)) + 0.5) * cell)
    }

    var boardCenter: CGPoint { CGPoint(x: origin.x + boardWidth / 2, y: origin.y + boardWidth / 2) }
    private func trayHome(_ slot: Int) -> CGPoint { CGPoint(x: slotX[slot], y: trayY) }

    /** Centre of a piece whose top-left cell sits at `o`. */
    func center(_ shape: TileShape, _ o: Int) -> CGPoint {
        let p = point(o)
        return CGPoint(x: p.x + CGFloat(shape.cols - 1) / 2 * cell, y: p.y + CGFloat(shape.rows - 1) / 2 * cell)
    }

    fileprivate func blockSprite(_ tone: Int) -> TileSprite { blockSprites[Kt.mod(tone, blockSprites.count)] }
    fileprivate func gemSprite(_ gem: TileGem) -> TileSprite { gemSprites[gem.ordinal] }

    // MARK: Frame

    func tick(_ dt: CGFloat) {
        if session.paused { return }
        time += dt
        if timers.contains(where: { $0.at <= time }) {
            let due = timers.filter { $0.at <= time }
            timers.removeAll { $0.at <= time }
            for d in due { d.run() }
        }
        fx.removeAll { time > $0.end }
        for i in 0..<64 { if let l = lingering[i], time >= l.until { lingering[i] = nil } }
        if session.phase == .Playing && !busy && drag == nil {
            idle += min(dt, 0.1)
            let wait: CGFloat = session.isTutorial ? 1.2 : 8
            if idle > wait {
                idle = session.isTutorial ? -2.4 : -6
                showHint()
            }
        } else {
            idle = 0
        }
        if let h = hint, time > h.since + 2 * TileScene.HINT_LOOP { hint = nil }
        clock.frame &+= 1
    }

    private func after(_ delay: CGFloat, _ block: @escaping () -> Void) { timers.append((time + delay, block)) }

    func didStart() { idle = 0 }

    // MARK: Input

    func began(_ p: CGPoint) {
        idle = 0
        hint = nil
        if session.phase != .Playing || busy || drag != nil { return }
        for k in 0..<3 {
            guard let node = tray[k] else { continue }
            let home = trayHome(k)
            if abs(p.x - home.x) < boardWidth / 6 + 6 * density && abs(p.y - home.y) < cell * 1.7 {
                drag = (k, node)
                node.scale.start(time).to(1, 0.1)
                follow(p)
                TileSound.play(.Pick)
                session.notePick()
                return
            }
        }
    }

    func moved(_ p: CGPoint) { follow(p) }

    private func follow(_ p: CGPoint) {
        guard let node = drag?.node else { return }
        let lift = cell * 1.25 + CGFloat(node.piece.shape.rows) * cell / 2
        node.x.set(time, p.x)
        node.y.set(time, p.y - lift)
        updatePreview()
    }

    func ended() {
        guard let d = drag else { return }
        let slot = d.slot
        let node = d.node
        drag = nil
        let target = snapped
        clearPreview()
        if let target {
            let c = center(node.piece.shape, target)
            node.x.start(time).to(c.x, 0.05)
            node.y.start(time).to(c.y, 0.05)
            tray[slot] = nil
            after(0.05) { [weak self] in
                node.gone = true
                self?.commit(slot, target, node)
            }
            pending = node
        } else {
            returnToTray(node, slot)
            TileSound.play(.Bounce)
            session.noteInvalid()
        }
    }

    /** The piece flying the last few pixels into place. */
    private var pending: TrayNode?

    private func returnToTray(_ node: TrayNode, _ slot: Int) {
        let home = trayHome(slot)
        node.x.start(time).to(home.x, 0.18, .Out)
        node.y.start(time).to(home.y, 0.18, .Out)
        node.scale.start(time).to(trayScale, 0.18)
    }

    private static let candidates: [(Int, Int)] = [(0, 0), (0, -1), (0, 1), (-1, 0), (1, 0)]

    private func updatePreview() {
        guard let node = drag?.node else { return }
        let shape = node.piece.shape
        let pos = CGPoint(x: node.x.value(time), y: node.y.value(time))
        let topLeft = CGPoint(x: pos.x - CGFloat(shape.cols - 1) / 2 * cell, y: pos.y - CGFloat(shape.rows - 1) / 2 * cell)
        let c0 = Kt.roundToInt(Double((topLeft.x - origin.x) / cell - 0.5))
        let r0 = Kt.roundToInt(Double((topLeft.y - origin.y) / cell - 0.5))
        var target: Int? = nil
        for (dr, dc) in TileScene.candidates {
            let r = r0 + dr
            let c = c0 + dc
            if r < 0 || c < 0 || r + shape.rows > 8 || c + shape.cols > 8 { continue }
            let o = TileGrid.index(r, c)
            if board.canPlace(shape, o) { target = o; break }
            if dr == 0 && dc == 0 && abs(topLeft.x - point(o).x) < cell * 0.3 && abs(topLeft.y - point(o).y) < cell * 0.3 { break }
        }
        if target == snapped { return }
        clearPreview()
        snapped = target
        guard let target else { return }
        let lines = board.wouldClear(shape, target)
        glowRows = lines.rows
        glowCols = lines.cols
        glowSince = time
        tintTone = shape.tone
        var cells: UInt64 = 0
        for r in lines.rows { cells |= TileGrid.rowMasks[r] }
        for c in lines.cols { cells |= TileGrid.colMasks[c] }
        var mask: UInt64 = 0
        for i in TileGrid.cells(cells) where board.blocks[i] != nil { mask |= TileGrid.bit(i) }
        tinted = mask
    }

    private func clearPreview() {
        snapped = nil
        glowRows = []
        glowCols = []
        tinted = 0
    }

    // MARK: Placing

    private func commit(_ slot: Int, _ o: Int, _ node: TrayNode) {
        pending = nil
        guard let turn = session.place(slot, o) else {
            if let piece = session.tray[slot] {
                let c = center(piece.shape, o)
                let fresh = TrayNode(piece, c.x, c.y, 1)
                tray[slot] = fresh
                returnToTray(fresh, slot)
            }
            return
        }
        let duration = animate(turn.placement)
        if let dealt = turn.dealt { after(min(0.35, duration * 0.5) + 0.05) { [weak self] in self?.deal(dealt) } }
        switch turn.outcome {
        case .Going:
            break
        case .Won:
            busy = true
            after(duration + 0.35) { [weak self] in self?.winSequence() }
        case .Stuck:
            busy = true
            let wait = max(duration, turn.dealt == nil ? 0 : 0.7) + 0.35
            after(wait) { [weak self] in self?.greyOut() }
        }
    }

    /** Animates a placement and returns how long the clear takes. */
    private func animate(_ p: TilePlacement) -> CGFloat {
        TileSound.play(.Place, 20)
        var clearedCells: UInt64 = 0
        for c in p.cleared { clearedCells |= TileGrid.bit(c.cell) }
        for i in p.cells where clearedCells & TileGrid.bit(i) == 0 { blockScale[i].set(time, 1.12).to(0.96, 0.07).to(1, 0.06) }
        if p.feverEnded { endFever() }
        if p.lines == 0 { return 0.12 }

        let maxDistance = CGFloat(p.cleared.map(\.distance).max() ?? 0)
        let step: CGFloat = reduceMotion ? 0.012 : 0.034
        let pieceTone = p.piece.shape.tone
        for c in p.cleared {
            let delay = 0.06 + CGFloat(c.distance) * step
            fx.append(ClearPop(time, point(c.cell), pieceTone, delay))
            let at = point(c.cell)
            after(0.06 + delay) { [weak self] in self?.burst(at, pieceTone) }
        }
        let tone = Kt.mod(pieceTone, TileArt.tones.count)
        for r in p.rows { beam(CGPoint(x: boardCenter.x, y: point(TileGrid.index(r, 0)).y), false, tone) }
        for c in p.cols { beam(CGPoint(x: point(TileGrid.index(0, c)).x, y: boardCenter.y), true, tone) }

        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for c in p.cleared { let pt = point(c.cell); sx += pt.x; sy += pt.y }
        let n = CGFloat(max(1, p.cleared.count))
        let mid = CGPoint(x: sx / n, y: sy / n)
        scorePop(p.linePoints + p.bonusPoints, mid, TileArt.tones[tone])

        for g in p.gems { flyGem(g.gem, point(g.cell), g.goal, 0.1) }

        TileSound.play(.Clear((p.combo - 1).coerceIn(0, 13)), 40)
        if p.lines >= 2 { TileSound.play(.Multi, 100) }
        if p.combo >= 2 {
            TileSound.play(.Combo, 150)
            comboBadge(p.combo, mid)
        }
        if let praise = p.praise {
            let y = mid.y < boardCenter.y ? origin.y + boardWidth - cell * 1.6 : origin.y + cell * 1.4
            after(0.12) { [weak self] in self?.praise(praise, y) }
        }
        if p.perfect { after(0.35) { [weak self] in self?.perfectClear() } }
        if p.feverStarted { startFever(true) }
        shake(min(9, CGFloat(p.lines) * 2.6) * density)
        return 0.06 + maxDistance * step + 0.2
    }

    private func deal(_ pieces: [TilePiece]) {
        TileSound.play(.Deal)
        for (k, piece) in pieces.enumerated() {
            let node = TrayNode(piece, slotX[k], trayY + cell * 1.4, 0.01)
            let d = CGFloat(k) * 0.06
            node.y.set(time, trayY + cell * 1.4).wait(d).to(trayY, 0.26, .Out)
            node.scale.set(time, 0.01).wait(d).to(trayScale * 1.15, 0.18).to(trayScale, 0.1)
            tray[k] = node
        }
    }

    // MARK: Endings

    private func greyOut() {
        greyed = true
        TileSound.play(.GameOver)
        for i in 0..<64 where board.blocks[i] != nil { grey[i].set(time, 0).wait(CGFloat(TileGrid.row(i)) * 0.045).to(0.75, 0.12) }
        trayAlpha.start(time).to(0.5, 0.3)
        banner("Out of space!", 0xFFFFFF, 0x3B2C8F, 0.3)
        after(1.1) { [weak self] in
            self?.busy = false
            self?.session.showNoSpace()
        }
    }

    func animateRevive(_ cleared: [TileCleared], _ newTray: [TilePiece?]) {
        greyed = false
        TileSound.play(.Revive)
        for i in 0..<64 { grey[i].start(time).to(0, 0.2) }
        trayAlpha.set(time, 1)
        for c in cleared {
            let hideAt = time + 0.1 + CGFloat(c.distance) * 0.06
            lingering[c.cell] = (c.block, hideAt)
            let at = point(c.cell)
            let tone = c.block.tone
            after(hideAt - time) { [weak self] in self?.burst(at, tone) }
        }
        flash(boardCenter, 6)
        for k in 0..<3 { tray[k] = nil }
        let pieces = newTray.compactMap { $0 }
        after(0.4) { [weak self] in self?.deal(pieces) }
    }

    private func winSequence() {
        TileSound.play(.Win)
        banner("Level complete!", 0xFFF27A, 0xC2410C, 0)
        for k in 0..<(reduceMotion ? 4 : 16) {
            let p = CGPoint(x: origin.x + CGFloat.random(in: 0..<1) * boardWidth, y: origin.y + CGFloat.random(in: 0..<1) * boardWidth)
            after(CGFloat(k) * 0.05) { [weak self] in self?.sparkles(p, 3) }
        }
        after(1.2) { [weak self] in
            self?.busy = false
            self?.session.finishWin()
        }
    }

    // MARK: Effects

    private final class ClearPop: Fx {
        let c: CGPoint
        let tone: Int
        let delay: CGFloat

        init(_ start: CGFloat, _ c: CGPoint, _ tone: Int, _ delay: CGFloat) {
            self.c = c
            self.tone = tone
            self.delay = delay
            super.init(start, end: start + 0.06 + delay + 0.14)
        }

        override func draw(_ ctx: GraphicsContext, _ s: TileScene, _ t: CGFloat) {
            let local = t - start
            let white = clamp01(local / 0.06) * 0.65
            let popT = clamp01((local - 0.06 - delay) / 0.14)
            let sc = 1 + 0.3 * popT
            let alpha = 1 - popT
            ctx.sprite(s.blockSprite(tone), c, s.cell * sc, s.cell * sc, alpha)
            if white > 0 { ctx.sprite(s.flashSquare, c, s.cell * sc * 0.93, s.cell * sc * 0.93, white * alpha) }
        }
    }

    private func burst(_ p: CGPoint, _ tone: Int) {
        let t = Kt.mod(tone, TileArt.tones.count)
        for _ in 0..<(reduceMotion ? 2 : 5) {
            let angle = CGFloat.random(in: 0..<1) * 2 * .pi
            let speed = cell * (0.8 + CGFloat.random(in: 0..<1) * 0.9)
            let end = CGPoint(x: p.x + cos(angle) * speed, y: p.y - sin(angle) * speed + cell * 0.9)
            let ctrl = CGPoint(x: p.x + cos(angle) * speed * 0.6, y: p.y - sin(angle) * speed - cell * 0.5)
            fx.append(Shard(time, p, ctrl, end, cell * (0.2 + CGFloat.random(in: 0..<1) * 0.14), CGFloat.random(in: 0..<1) * 6.28,
                            (CGFloat.random(in: 0..<1) - 0.5) * 10, shardSprites[t]))
        }
        if Int.random(in: 0..<3) == 0 { sparkles(p, 1) }
    }

    private final class Shard: Fx {
        let p0: CGPoint
        let ctrl: CGPoint
        let p1: CGPoint
        let s: CGFloat
        let rot0: CGFloat
        let spin: CGFloat
        let sprite: TileSprite

        init(_ start: CGFloat, _ p0: CGPoint, _ ctrl: CGPoint, _ p1: CGPoint, _ s: CGFloat, _ rot0: CGFloat, _ spin: CGFloat, _ sprite: TileSprite) {
            self.p0 = p0
            self.ctrl = ctrl
            self.p1 = p1
            self.s = s
            self.rot0 = rot0
            self.spin = spin
            self.sprite = sprite
            super.init(start, end: start + 0.45)
        }

        override func draw(_ ctx: GraphicsContext, _ scene: TileScene, _ t: CGFloat) {
            let x = clamp01((t - start) / 0.45)
            let u = 1 - x
            let pos = CGPoint(x: u * u * p0.x + 2 * u * x * ctrl.x + x * x * p1.x, y: u * u * p0.y + 2 * u * x * ctrl.y + x * x * p1.y)
            let alpha: CGFloat = t - start < 0.25 ? 1 : 1 - clamp01((t - start - 0.25) / 0.2)
            ctx.sprite(sprite, pos, s, s, alpha, rot0 + spin * x)
        }
    }

    private func sparkles(_ p: CGPoint, _ count: Int) {
        for _ in 0..<count {
            let s = cell * (0.35 + CGFloat.random(in: 0..<1) * 0.25)
            let pos = CGPoint(x: p.x + (CGFloat.random(in: 0..<1) - 0.5) * cell * 0.8, y: p.y + (CGFloat.random(in: 0..<1) - 0.5) * cell * 0.8)
            fx.append(Sparkle(time, pos, s))
        }
    }

    private final class Sparkle: Fx {
        let p: CGPoint
        let s: CGFloat

        init(_ start: CGFloat, _ p: CGPoint, _ s: CGFloat) {
            self.p = p
            self.s = s
            super.init(start, end: start + 0.62)
        }

        override func draw(_ ctx: GraphicsContext, _ scene: TileScene, _ t: CGFloat) {
            let local = t - start
            let sc = 0.1 + 0.9 * clamp01(local / 0.15)
            let rot = 1.2 * clamp01(local / 0.4)
            let alpha: CGFloat = local < 0.4 ? 1 : 1 - clamp01((local - 0.4) / 0.22)
            ctx.sprite(TileArt.sparkle, p, s * sc, s * sc, alpha, rot, blend: .plusLighter)
        }
    }

    private func flash(_ p: CGPoint, _ scale: CGFloat) { fx.append(Flash(time, p, cell * scale)) }

    private final class Flash: Fx {
        let p: CGPoint
        let s: CGFloat

        init(_ start: CGFloat, _ p: CGPoint, _ s: CGFloat) {
            self.p = p
            self.s = s
            super.init(start, end: start + 0.25)
        }

        override func draw(_ ctx: GraphicsContext, _ scene: TileScene, _ t: CGFloat) {
            let local = t - start
            let sc = 0.3 + 1.0 * clamp01(local / 0.2)
            ctx.sprite(TileArt.glow, p, s * sc, s * sc, 1 - clamp01(local / 0.25), blend: .plusLighter)
        }
    }

    private func beam(_ p: CGPoint, _ vertical: Bool, _ tone: Int) {
        fx.append(Beam(time, p, vertical, TileArt.beam, 0.55, 1))
        fx.append(Beam(time, p, vertical, beamSprites[tone], 1.15, 0.7))
    }

    private final class Beam: Fx {
        let p: CGPoint
        let vertical: Bool
        let sprite: TileSprite
        let thick: CGFloat
        let alpha0: CGFloat

        init(_ start: CGFloat, _ p: CGPoint, _ vertical: Bool, _ sprite: TileSprite, _ thick: CGFloat, _ alpha0: CGFloat) {
            self.p = p
            self.vertical = vertical
            self.sprite = sprite
            self.thick = thick
            self.alpha0 = alpha0
            super.init(start, end: start + 0.4)
        }

        override func draw(_ ctx: GraphicsContext, _ s: TileScene, _ t: CGFloat) {
            let local = t - start
            let sx = 0.05 + 0.95 * clamp01(local / 0.14)
            let fade = clamp01((local - 0.14) / 0.26)
            let sy = 1 - 0.7 * fade
            let w = (s.boardWidth + s.cell * 1.2) * sx
            let h = s.cell * thick * sy
            ctx.sprite(sprite, p, w, h, alpha0 * (1 - fade), vertical ? .pi / 2 : 0, blend: .plusLighter)
        }
    }

    private func label(_ text: String, _ size: CGFloat, _ fill: Int, _ stroke: Int) -> TileLabel {
        TileArt.label(text, size, fill, stroke)
    }

    private final class ScorePop: Fx {
        let l: TileLabel
        let p: CGPoint
        let x: CGFloat

        init(_ start: CGFloat, _ l: TileLabel, _ p: CGPoint, _ x: CGFloat) {
            self.l = l
            self.p = p
            self.x = x
            super.init(start, end: start + 0.8)
        }

        override func draw(_ ctx: GraphicsContext, _ s: TileScene, _ t: CGFloat) {
            let local = t - start
            let y = p.y - s.cell * 0.9 * (local / 0.8)
            let sc: CGFloat = local < 0.12 ? 0.5 + 0.65 * (local / 0.12) : 1.15 - 0.15 * clamp01((local - 0.12) / 0.1)
            let alpha: CGFloat = local < 0.45 ? 1 : 1 - clamp01((local - 0.45) / 0.3)
            var g = ctx
            g.translateBy(x: x, y: y)
            g.scaleBy(x: sc, y: sc)
            g.label(l, .zero, alpha)
        }
    }

    private func scorePop(_ value: Int, _ p: CGPoint, _ tone: Int) {
        if value <= 0 { return }
        let l = label("+\(value)", cell * (value >= 100 ? 0.72 : 0.56), 0xFFFFFF, tone)
        let x = min(max(p.x, origin.x + cell * 1.3), origin.x + boardWidth - cell * 1.3)
        fx.append(ScorePop(time, l, p, x))
    }

    private func comboBadge(_ combo: Int, _ p: CGPoint) {
        fx.removeAll { $0 is ComboFx }
        let word = label("Combo", cell * 0.62, 0xFFFFFF, 0x4B2FD8)
        let number = label("×\(combo)", cell * 0.95, 0xFFD35A, 0xC2410C)
        let x = min(max(p.x, origin.x + cell * 2.2), origin.x + boardWidth - cell * 2.7)
        let y = p.y + cell * 1.3 <= origin.y + boardWidth - cell * 0.5 ? p.y + cell * 1.3 : p.y - cell * 1.3
        fx.append(ComboFx(time, CGPoint(x: x, y: y), word, number))
    }

    private final class ComboFx: Fx {
        let c: CGPoint
        let word: TileLabel
        let number: TileLabel

        init(_ start: CGFloat, _ c: CGPoint, _ word: TileLabel, _ number: TileLabel) {
            self.c = c
            self.word = word
            self.number = number
            super.init(start, end: start + 1.02)
        }

        override func draw(_ ctx: GraphicsContext, _ s: TileScene, _ t: CGFloat) {
            let local = t - start
            let sc: CGFloat
            if local < 0.14 { sc = 0.2 + 0.92 * (local / 0.14) } else if local < 0.22 { sc = 1.12 - 0.12 * ((local - 0.14) / 0.08) } else { sc = 1 }
            let out = clamp01((local - 0.77) / 0.25)
            let pos = CGPoint(x: c.x, y: c.y - s.cell * 0.5 * out)
            var g = ctx
            g.translateBy(x: pos.x, y: pos.y)
            g.rotate(by: .radians(-0.06))
            g.scaleBy(x: sc, y: sc)
            g.label(word, CGPoint(x: -s.cell * 0.75, y: 0), 1 - out)
            let np = CGPoint(x: s.cell * 1.6, y: 0)
            g.label(number, np, 1 - out)
            let rs = s.cell * 1.7 * (0.3 + 0.9 * clamp01(local / 0.3))
            g.sprite(TileArt.ring, np, rs, rs, 1 - clamp01(local / 0.35), blend: .plusLighter)
        }
    }

    private func praise(_ level: Int, _ y: CGFloat) {
        let fills = [0xFFFFFF, 0xFFF27A, 0x9CF5FF, 0xFFB3F0, 0xFFD45C]
        let strokes = [0x3B5BDB, 0xD6246E, 0x2B6BE0, 0x9B2BD8, 0xE0561B]
        let k = level.coerceIn(0, TileBoard.PRAISE_WORDS.count - 1)
        banner(TileBoard.PRAISE_WORDS[k], fills[k], strokes[k], 0, y)
    }

    private final class PerfectRing: Fx {
        init(_ start: CGFloat) { super.init(start, end: start + 0.4) }

        override func draw(_ ctx: GraphicsContext, _ s: TileScene, _ t: CGFloat) {
            let local = t - start
            let sz = s.boardWidth * 1.3 * (0.1 + 0.9 * (local / 0.4))
            let a: CGFloat = local < 0.2 ? 1 : 1 - (local - 0.2) / 0.2
            ctx.sprite(TileArt.ring, s.boardCenter, sz, sz, a, blend: .plusLighter)
        }
    }

    private func perfectClear() {
        TileSound.play(.Perfect)
        fx.append(PerfectRing(time))
        flash(boardCenter, 9)
        banner("Perfect!", 0xFFFFFF, 0xE01B8C, 0.1)
        shake(10 * density)
    }

    private final class BannerFx: Fx {
        let l: TileLabel
        let c: CGPoint

        init(_ start: CGFloat, _ l: TileLabel, _ c: CGPoint) {
            self.l = l
            self.c = c
            super.init(start, end: start + 1.01)
        }

        override func draw(_ ctx: GraphicsContext, _ s: TileScene, _ t: CGFloat) {
            let local = t - start
            let sc: CGFloat
            let rot: CGFloat
            if local < 0.16 {
                let x = local / 0.16
                sc = 0.1 + 1.05 * x
                rot = -0.06 + 0.08 * x
            } else if local < 0.26 {
                sc = 1.15 - 0.15 * ((local - 0.16) / 0.1)
                rot = 0.02
            } else {
                sc = 1
                rot = 0.02
            }
            let out = clamp01((local - 0.76) / 0.25)
            let pos = CGPoint(x: c.x, y: c.y - s.cell * 0.8 * out)
            var g = ctx
            g.translateBy(x: pos.x, y: pos.y)
            g.rotate(by: .radians(Double(rot)))
            g.scaleBy(x: sc, y: sc)
            g.label(l, .zero, 1 - out)
        }
    }

    func banner(_ text: String, _ fill: Int, _ stroke: Int, _ delay: CGFloat, _ y: CGFloat? = nil) {
        let show = { [weak self] in
            guard let self else { return }
            self.fx.removeAll { $0 is BannerFx }
            let l = self.label(text, min(54 * self.density, self.cell * 1.15), fill, stroke)
            let c = CGPoint(x: self.boardCenter.x, y: y ?? (self.origin.y + self.cell * 1.4))
            self.fx.append(BannerFx(self.time, l, c))
            if !self.reduceMotion { self.sparkles(c, 4) }
        }
        if delay > 0 { after(delay, show) } else { show() }
    }

    private final class FlyGem: Fx {
        let sprite: TileSprite
        let from: CGPoint
        let ctrl: CGPoint
        let target: CGPoint
        let delay: CGFloat
        let dur: CGFloat

        init(_ start: CGFloat, _ sprite: TileSprite, _ from: CGPoint, _ ctrl: CGPoint, _ target: CGPoint, _ delay: CGFloat, _ dur: CGFloat) {
            self.sprite = sprite
            self.from = from
            self.ctrl = ctrl
            self.target = target
            self.delay = delay
            self.dur = dur
            super.init(start, end: start + delay + 0.1 + dur)
        }

        override func draw(_ ctx: GraphicsContext, _ s: TileScene, _ t: CGFloat) {
            let local = t - start - delay
            let size = s.cell * 0.8
            if local < 0 { ctx.sprite(sprite, from, size, size); return }
            if local < 0.1 {
                let sc = 1 + 0.35 * local / 0.1
                ctx.sprite(sprite, from, size * sc, size * sc)
                return
            }
            let x = clamp01((local - 0.1) / dur)
            let e = x * x
            let u = 1 - e
            let pos = CGPoint(x: u * u * from.x + 2 * u * e * ctrl.x + e * e * target.x, y: u * u * from.y + 2 * u * e * ctrl.y + e * e * target.y)
            let sc = 1.35 - 0.75 * x
            ctx.sprite(sprite, pos, size * sc, size * sc, 1, x * 2 * .pi)
        }
    }

    private func flyGem(_ gem: TileGem, _ from: CGPoint, _ goal: Int?, _ delay: CGFloat) {
        let target = goal.flatMap { goalTargets[$0] }.map(scenePoint) ?? CGPoint(x: from.x, y: from.y - cell * 3)
        let ctrl = CGPoint(x: from.x + (target.x - from.x) * 0.2 + (CGFloat.random(in: 0..<1) * 2 - 1) * cell, y: min(from.y, target.y) - cell)
        let dur: CGFloat = reduceMotion ? 0.3 : 0.65
        fx.append(FlyGem(time, gemSprite(gem), from, ctrl, target, delay, dur))
        after(delay + 0.1 + dur) { [weak self] in
            TileSound.play(.Gem, 50)
            if let goal { self?.session.goalTick(goal) }
        }
    }

    // MARK: Fever

    private func startFever(_ animated: Bool) {
        feverFadeOut = nil
        if animated {
            TileSound.play(.FeverStart)
            banner("Fever ×2!", 0xFFE27A, 0xD9480F, 0.45)
            feverAlpha.start(time).to(1, reduceMotion ? 0.01 : 0.4)
        } else {
            feverAlpha.set(time, 1)
        }
        feverSince = time
    }

    private func endFever() {
        TileSound.play(.FeverEnd)
        feverAlpha.start(time).to(0, 0.4)
        feverFadeOut = time
    }

    private func shake(_ amount: CGFloat) {
        if reduceMotion || amount <= 0 { return }
        shakeX.set(time, 0).to(amount, 0.03).to(-amount, 0.05).to(amount * 0.4, 0.04).to(0, 0.04)
        shakeY.set(time, 0).to(amount * 0.5, 0.03).to(-amount * 0.5, 0.05).to(0, 0.04).to(0, 0.04)
    }

    // MARK: Hint

    private func showHint() {
        if hint != nil { return }
        guard let move = session.hint() else { return }
        if session.tray[move.0] == nil { return }
        hint = (move.0, move.1, time)
    }

    // MARK: Drawing

    /// Draws everything above the backdrop (the view shows `backgroundSprite` underneath), in pixels.
    func draw(_ base: GraphicsContext) {
        guard laidOut else { return }
        let t = time
        var ctx = base
        ctx.translateBy(x: shakeX.value(t), y: shakeY.value(t))
        let side = boardWidth + margin * 2
        let fa = feverAlpha.value(t)
        // Fever glow behind the board.
        if fa > 0.01 {
            let since = feverSince ?? t
            let pulse: CGFloat = reduceMotion ? 0.5 : 0.55 + 0.15 * sin((t - since) * .pi)
            ctx.sprite(feverGlow, boardCenter, boardWidth * 1.7, boardWidth * 1.7, pulse * fa, blend: .plusLighter)
        }
        ctx.sprite(boardSprite, boardCenter, side, side)
        if fa > 0.01 { ctx.sprite(feverBoardSprite, boardCenter, side, side, fa) }
        // Tray shelf.
        ctx.fill(shelf, with: .color(.white.opacity(0.1)))
        ctx.stroke(shelf, with: .color(.white.opacity(0.16)), style: shelfStroke)

        // Blocks.
        let breath: CGFloat = reduceMotion ? 1 : 1.02 + 0.06 * sin(t / 0.7 * .pi)
        for i in 0..<64 {
            guard let block = board.blocks[i] ?? lingering[i]?.block else { continue }
            let p = point(i)
            let sc = blockScale[i].value(t)
            let tone = tinted & TileGrid.bit(i) != 0 ? tintTone : block.tone
            ctx.sprite(blockSprite(tone), p, cell * sc, cell * sc)
            let g = grey[i].value(t)
            if g > 0.01 { ctx.sprite(greySquare, p, cell * sc * 0.93, cell * sc * 0.93, g * 0.9) }
            if let gem = block.gem {
                ctx.sprite(gemSprite(gem), p, cell * 0.74 * breath * sc, cell * 0.74 * breath * sc, g > 0 ? 1 - g * 0.5 : 1)
            }
        }

        // Ghost and line glows.
        let dragged = drag?.node
        if let target = snapped, let dragged {
            let shape = dragged.piece.shape
            let r = TileGrid.row(target)
            let c = TileGrid.col(target)
            let pulse = 0.65 + 0.2 * cos((t - glowSince) / 0.3 * .pi)
            let glow = lineGlowSprites[Kt.mod(shape.tone, lineGlowSprites.count)]
            for row in glowRows {
                let y = point(TileGrid.index(row, 0)).y
                ctx.sprite(glow, CGPoint(x: boardCenter.x, y: y), boardWidth + cell * 0.2, cell * 1.1, pulse, blend: .plusLighter)
            }
            for col in glowCols {
                let x = point(TileGrid.index(0, col)).x
                ctx.sprite(glow, CGPoint(x: x, y: boardCenter.y), cell * 1.1, boardWidth + cell * 0.2, pulse, blend: .plusLighter)
            }
            let img = blockSprite(shape.tone)
            for (dr, dc) in shape.cells {
                let p = point(TileGrid.index(r + dr, c + dc))
                ctx.sprite(img, p, cell, cell, 0.45)
                ctx.sprite(outlineSprite, p, cell, cell)
            }
        }

        // Effects.
        for f in fx { f.draw(ctx, self, t) }

        // Tray and the piece in flight.
        let ta = trayAlpha.value(t)
        for k in 0..<3 {
            guard let node = tray[k] else { continue }
            if node === dragged { continue }
            drawPiece(ctx, node, t, ta)
        }
        if let pending { drawPiece(ctx, pending, t, 1) }
        if let dragged { drawPiece(ctx, dragged, t, 1) }

        // Fever bulbs ring the frame.
        if fa > 0.01 {
            let s = boardWidth + margin * 1.2
            let perSide = 9
            var k = 0
            let since = feverSince ?? t
            for sideIndex in 0..<4 {
                for j in 0..<perSide {
                    let f = CGFloat(j) / CGFloat(perSide)
                    let local: CGPoint
                    switch sideIndex {
                    case 0: local = CGPoint(x: -s / 2 + s * f, y: -s / 2)
                    case 1: local = CGPoint(x: s / 2, y: -s / 2 + s * f)
                    case 2: local = CGPoint(x: s / 2 - s * f, y: s / 2)
                    default: local = CGPoint(x: -s / 2, y: s / 2 - s * f)
                    }
                    let a: CGFloat
                    if reduceMotion {
                        a = 1
                    } else {
                        let ph = ((t - since - CGFloat(k % 4) * 0.12).truncatingRemainder(dividingBy: 0.48) + 0.48).truncatingRemainder(dividingBy: 0.48)
                        a = ph < 0.12 ? 0.3 + 0.7 * ph / 0.12 : 1 - 0.75 * (ph - 0.12) / 0.36
                    }
                    let bc = boardCenter
                    ctx.sprite(TileArt.bulb, CGPoint(x: bc.x + local.x, y: bc.y + local.y), margin * 1.3, margin * 1.3, a * fa, blend: .plusLighter)
                    k += 1
                }
            }
        }

        // Hint: a ghost of the piece glides from the tray to a good spot, with a hand.
        if let h = hint, let piece = session.tray[h.slot] {
            let local = (t - h.since).truncatingRemainder(dividingBy: TileScene.HINT_LOOP)
            let from = trayHome(h.slot)
            let to = center(piece.shape, h.origin)
            let travel = reduceMotion ? 1 : ease(.InOut, clamp01((local - 0.2) / 0.9))
            let pos = CGPoint(x: from.x + (to.x - from.x) * travel, y: from.y + (to.y - from.y) * travel)
            let alpha: CGFloat
            if local < 0.2 { alpha = local / 0.2 } else if local < 1.6 { alpha = 1 } else { alpha = 1 - clamp01((local - 1.6) / 0.25) }
            let sc = trayScale + (1 - trayScale) * clamp01((local - 0.2) / 0.3)
            drawPieceAt(ctx, piece, pos, sc, 0.55 * alpha)
            let hs = cell * 1.2
            let x = pos.x - hs * 0.25 + cell * 0.1
            let y = pos.y - hs * 0.1 + cell * 0.2
            if alpha > 0.003 {
                var g = ctx
                if alpha < 1 { g.opacity = Double(alpha) }
                g.draw(TileArt.hand.image, in: CGRect(x: x, y: y, width: hs, height: hs))
            }
        }
    }

    private func drawPiece(_ ctx: GraphicsContext, _ node: TrayNode, _ t: CGFloat, _ alpha: CGFloat) {
        drawPieceAt(ctx, node.piece, CGPoint(x: node.x.value(t), y: node.y.value(t)), node.scale.value(t), alpha * node.alpha.value(t))
    }

    private func drawPieceAt(_ ctx: GraphicsContext, _ piece: TilePiece, _ c: CGPoint, _ sc: CGFloat, _ alpha: CGFloat) {
        let shape = piece.shape
        let img = blockSprite(shape.tone)
        let size = cell * sc
        for (k, rc) in shape.cells.enumerated() {
            let p = CGPoint(x: c.x + (CGFloat(rc.1) - CGFloat(shape.cols - 1) / 2) * size, y: c.y + (CGFloat(rc.0) - CGFloat(shape.rows - 1) / 2) * size)
            ctx.sprite(img, p, size, size, alpha)
            if k == piece.gemCell, let gem = piece.gem { ctx.sprite(gemSprite(gem), p, cell * 0.74 * sc, cell * 0.74 * sc, alpha) }
        }
    }
}
