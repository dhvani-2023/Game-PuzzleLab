import SwiftUI
import Observation
import GameKit

/// Seconds since the play screen opened, ticked every display frame (GameKit `GameLoop`, 120 Hz) while
/// something on the board is moving. Views redraw on `frame`; the settled layer redraws on `staticKey`.
/// The loop sleeps once every animation has settled and wakes on the next event, so an idle board costs nothing.
@MainActor
@Observable
final class FxClock {
    @ObservationIgnored private(set) var now: Float = 0
    /// Bumped every frame while the board animates.
    private(set) var frame = 0
    /// Bumped when the settled layer (board, finished lines and scribbles) has to redraw.
    private(set) var staticKey = 0

    @ObservationIgnored var fx: BoxFx? { didSet { if fx !== oldValue { staticKey &+= 1; wake() } } }
    @ObservationIgnored private let loop = GameLoop()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var idleFrames = 0

    init() {
        loop.onTick = { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    /// Restarts the frame clock after an event (drag, commit, capture…).
    func wake() {
        idleFrames = 0
        if running { return }
        running = true
        loop.start()
    }

    func stop() {
        running = false
        loop.stop()
    }

    private func step() {
        now = Float(loop.time)
        guard let fx else { return }
        let (busy, changed) = fx.tick(now)
        if changed { staticKey &+= 1 }
        if busy {
            idleFrames = 0
            frame &+= 1
        } else {
            idleFrames += 1
            if idleFrames == 1 { frame &+= 1 } // draw the settled state once more
            if idleFrames > 3 { stop() }
        }
    }
}

/// Step response of a damped spring: 0 at t=0, settles at 1 (overshooting when damping < 1).
func springStep(_ t: Float, _ response: Float = 0.34, _ damping: Float = 0.42) -> Float {
    if t <= 0 { return 0 }
    let w = 2.0 * Double.pi / Double(response)
    let z = Double(damping)
    let wd = w * (1 - z * z).squareRoot()
    let td = Double(t)
    return Float(1 - exp(-z * w * td) * (cos(wd * td) + z * w / wd * sin(wd * td)))
}

private func easeInOut(_ t: Float) -> Float { let x = min(max(t, 0), 1); return x * x * (3 - 2 * x) }
private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Float) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
}
private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Float) -> CGFloat { a + (b - a) * CGFloat(t) }

/// Dot-grid geometry for a canvas size.
struct BoardGeom {
    let origin: CGPoint
    let cell: CGFloat
    let rows: Int
    let cols: Int
    let side: CGFloat
    let m: BoxMetrics

    init(_ origin: CGPoint, _ cell: CGFloat, _ rows: Int, _ cols: Int, _ side: CGFloat) {
        self.origin = origin
        self.cell = cell
        self.rows = rows
        self.cols = cols
        self.side = side
        m = BoxMetrics(cell, side)
    }

    func dot(_ r: Int, _ c: Int) -> CGPoint { CGPoint(x: origin.x + CGFloat(c) * cell, y: origin.y + CGFloat(r) * cell) }
    func dot(_ i: Int) -> CGPoint { dot(i / (cols + 1), i % (cols + 1)) }
    func index(_ r: Int, _ c: Int) -> Int { r * (cols + 1) + c }
    func ends(_ e: BoxEdge) -> (Int, Int) {
        e.horizontal ? (index(e.r, e.c), index(e.r, e.c + 1)) : (index(e.r, e.c), index(e.r + 1, e.c))
    }
    func boxCenter(_ r: Int, _ c: Int) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(c) + 0.5) * cell, y: origin.y + (CGFloat(r) + 0.5) * cell)
    }

    static func of(_ width: CGFloat, _ height: CGFloat, _ rows: Int, _ cols: Int) -> BoardGeom {
        let side = min(width, height)
        let inset = side * 0.105
        let cell = min((width - 2 * inset) / CGFloat(cols), (height - 2 * inset) / CGFloat(rows))
        return BoardGeom(CGPoint(x: (width - cell * CGFloat(cols)) / 2, y: (height - cell * CGFloat(rows)) / 2), cell, rows, cols, side)
    }
}

/// Every animation on the Box Battle board, timed off [FxClock]: the live drag line, line springs, the
/// bot's pencil, box captures (scribble, glow trace, gold corners) and the "+1"s.
///
/// Drawing is split in two layers so a busy frame stays cheap: `drawStatic` (board card, settled lines and
/// scribbles — redrawn only when `tick` reports a change) and `drawDynamic` (everything still moving,
/// every dot and the pencils — redrawn each frame). Together they paint exactly what the Android board
/// paints in one pass.
@MainActor
final class BoxFx {
    private let speed: Float

    // Committed lines that are still springing into their dog-bone shape.
    private struct LineAnim {
        let start: Float
        let grow: Float
        let fromB: Bool
    }
    private var lines: [BoxEdge: LineAnim] = [:]

    // The bot's line being drawn by its pencil (not yet in the model).
    private(set) var pending: BoxEdge?
    private var pendingStart: Float = 0
    private var pendingFromB = false
    let pencilSeconds: Float

    // The player's live drag.
    private(set) var dragDot = -1
    private var dragStart: Float = 0
    private(set) var dragHead: CGPoint?
    private(set) var hoverDot = -1
    private var hoverStart: Float = 0
    private var retractDot = -1
    private var retractFrom = CGPoint.zero
    private var retractStart: Float = -9

    // Dots springing back after a release, and capture corners flashing gold.
    private var pulses: [Int: Float] = [:]
    private var golds: [Int: Float] = [:]

    final class Capture {
        let r: Int
        let c: Int
        let owner: Player
        let start: Float

        init(_ r: Int, _ c: Int, _ owner: Player, _ start: Float) {
            self.r = r
            self.c = c
            self.owner = owner
            self.start = start
        }
    }
    private var captures: [BoxCell: Capture] = [:]
    /// Captured boxes whose scribble is still being drawn (the rest live in the settled layer).
    private var liveScribbles = Set<BoxCell>()
    private(set) var flyers: [Capture] = []

    private(set) var geom: BoardGeom?

    private var scribbles: [BoxCell: Path] = [:]
    private var scribbleCell: CGFloat = 0
    private var pencils: [(tip: CGPoint, owner: Player, k: CGFloat)] = []

    static let SCRIBBLE_AT: Float = 0.16
    static let SCRIBBLE_FOR: Float = 0.7
    static let GOLD_AT: Float = 0.9
    static let GOLD_FOR: Float = 0.45
    static let FLY_FOR: Float = 0.68
    /// How long a capture takes to play out (the bot waits this long before moving on).
    static let CAPTURE_SECONDS: Float = 1.1

    init(_ reduceMotion: Bool) {
        speed = reduceMotion ? 40 : 1
        pencilSeconds = reduceMotion ? 0.02 : 0.4
    }

    /// Canvas size → geometry, remembered for events that need dot positions.
    func layout(_ size: CGSize, _ model: BoxModel) -> BoardGeom {
        if let g = geom, g.rows == model.rows, g.cols == model.cols, abs(g.side - min(size.width, size.height)) < 0.01 { return g }
        let g = BoardGeom.of(size.width, size.height, model.rows, model.cols)
        geom = g
        return g
    }

    // MARK: Events

    func beginDrag(_ dot: Int, _ now: Float) {
        dragDot = dot; dragStart = now; dragHead = nil; hoverDot = -1
    }

    /// Moves the live line; returns true when it just snapped onto a new target dot.
    func updateDrag(_ head: CGPoint, _ hover: Int, _ now: Float) -> Bool {
        dragHead = head
        if hover != hoverDot {
            if hoverDot >= 0 { pulses[hoverDot] = now }
            hoverDot = hover
            hoverStart = now
            return hover >= 0
        }
        return false
    }

    /// Finger lifted without reaching a dot: the line snaps back into its dot.
    func cancelDrag(_ now: Float) {
        if dragDot >= 0, let g = geom {
            retractDot = dragDot
            retractFrom = dragHead ?? g.dot(dragDot)
            retractStart = now
            pulses[dragDot] = now
        }
        if hoverDot >= 0 { pulses[hoverDot] = now }
        dragDot = -1; dragHead = nil; hoverDot = -1
    }

    func startPencil(_ e: BoxEdge, _ now: Float) {
        pending = e; pendingStart = now; pendingFromB = (e.r + e.c) % 2 == 1
    }

    /// A line has been committed to the model by `owner`.
    func commit(_ e: BoxEdge, _ now: Float, grow: Float = 0) {
        let fromB = pending == e && pendingFromB
        lines[e] = LineAnim(start: now, grow: grow / speed, fromB: fromB)
        if let g = geom {
            let (a, b) = g.ends(e)
            pulses[a] = now; pulses[b] = now
        }
        if pending == e { pending = nil }
        dragDot = -1; dragHead = nil; hoverDot = -1
    }

    func capture(_ r: Int, _ c: Int, _ owner: Player, _ now: Float) {
        let cap = Capture(r, c, owner, now)
        captures[BoxCell(r, c)] = cap
        liveScribbles.insert(BoxCell(r, c))
        flyers.removeAll { (now - $0.start) * speed > Self.FLY_FOR + 0.2 }
        flyers.append(cap)
        guard let g = geom else { return }
        let goldAt = now + Self.GOLD_AT / speed
        for (dr, dc) in [(0, 0), (0, 1), (1, 0), (1, 1)] { golds[g.index(r + dr, c + dc)] = goldAt }
    }

    /// Per-frame bookkeeping (runs before drawing): retires finished animations. Returns whether anything
    /// is still moving and whether the settled layer changed.
    func tick(_ now: Float) -> (busy: Bool, staticChanged: Bool) {
        var changed = false
        for (e, anim) in lines {
            let t = now - anim.start
            if t < anim.grow { continue }
            let s = springStep((t - anim.grow) * speed, 0.36, 0.32)
            if abs(1 - s) < 0.002 && t - anim.grow > 1 { lines[e] = nil; changed = true }
        }
        for b in liveScribbles {
            let cap = captures[b]
            let p = cap.map { ((now - $0.start) * speed - Self.SCRIBBLE_AT) / Self.SCRIBBLE_FOR } ?? 1
            if p >= 1 { liveScribbles.remove(b); changed = true }
        }
        for (b, cap) in captures where (now - cap.start) * speed > Self.GOLD_AT + 0.35 && !liveScribbles.contains(b) {
            captures[b] = nil
        }
        for (i, t) in pulses where now - t >= 1.2 { pulses[i] = nil }
        for (i, t) in golds where (now - t) * speed >= Self.GOLD_FOR { golds[i] = nil }
        if !flyers.isEmpty { flyers.removeAll { (now - $0.start) * speed > Self.FLY_FOR } }
        let retracting = retractDot >= 0 && (now - retractStart) / 0.16 < 1
        let busy = !lines.isEmpty || pending != nil || dragDot >= 0 || retracting || !pulses.isEmpty || !golds.isEmpty
            || !captures.isEmpty || !liveScribbles.isEmpty || !flyers.isEmpty
        return (busy, changed)
    }

    // MARK: Drawing

    private func scribble(_ r: Int, _ c: Int, _ g: BoardGeom) -> Path {
        if scribbleCell != g.cell { scribbles.removeAll(); scribbleCell = g.cell }
        if let p = scribbles[BoxCell(r, c)] { return p }
        let tl = g.dot(r, c)
        let pad = g.cell * 0.22
        let p = scribblePath(CGRect(x: tl.x + pad, y: tl.y + pad * 1.05, width: g.cell - 2 * pad, height: g.cell - pad - pad * 1.05), 31 * r + 7 * c + 11)
        scribbles[BoxCell(r, c)] = p
        return p
    }

    /// The settled layer: board card, finished scribbles and lines that have stopped springing.
    func drawStatic(_ ctx: GraphicsContext, _ size: CGSize, _ model: BoxModel) {
        let g = layout(size, model)
        let m = g.m
        ctx.boardCard(CGRect(origin: .zero, size: size), g.side * 0.085)

        // 1. Claimed boxes: crayon scribbles (glows batched into one blurred layer).
        var settledBoxes: [(Path, Player)] = []
        for r in 0..<model.rows {
            for c in 0..<model.cols {
                guard let owner = model.owner[r][c], !liveScribbles.contains(BoxCell(r, c)) else { continue }
                settledBoxes.append((scribble(r, c, g), owner))
            }
        }
        if !settledBoxes.isEmpty {
            let w = m.crayonW * 2.2
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: boxBlurSigma(max(w * 0.32, 0.5))))
                for (p, owner) in settledBoxes { l.stroke(p, with: .color(BoxArt.crayon(owner).opacity(0.65)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)) }
            }
            for (p, owner) in settledBoxes { ctx.crayon(p, BoxArt.crayon(owner), m.crayonW, 1, halo: false) }
        }

        // 2. Committed lines that have settled into the pinched dog-bone.
        var settled: [(CGPoint, CGPoint, Player)] = []
        for r in 0...model.rows {
            for c in 0..<model.cols {
                if let o = model.hOwner[r][c], lines[BoxEdge(true, r, c)] == nil { settled.append((g.dot(r, c), g.dot(r, c + 1), o)) }
            }
        }
        for r in 0..<model.rows {
            for c in 0...model.cols {
                if let o = model.vOwner[r][c], lines[BoxEdge(false, r, c)] == nil { settled.append((g.dot(r, c), g.dot(r + 1, c), o)) }
            }
        }
        if !settled.isEmpty {
            let w = m.endW * 1.45
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: boxBlurSigma(max(w * 0.32, 0.5))))
                for (a, b, o) in settled {
                    var p = Path()
                    p.move(to: a)
                    p.addLine(to: b)
                    l.stroke(p, with: .color(BoxArt.line(o).opacity(0.75)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                }
            }
            for (a, b, o) in settled { ctx.boneLine(a, b, m.endW, m.midW, BoxArt.line(o), halo: false) }
        }
    }

    /// Everything still moving, every dot and the pencils, drawn over the settled layer each frame.
    func drawDynamic(_ ctx: GraphicsContext, _ size: CGSize, _ model: BoxModel, _ now: Float) {
        let g = layout(size, model)
        let m = g.m
        pencils.removeAll(keepingCapacity: true)

        // 1. Claimed boxes still being scribbled in.
        for b in liveScribbles {
            guard let owner = model.owner[b.r][b.c] else { continue }
            let cap = captures[b]
            let p: Float = cap.map { min(max(((now - $0.start) * speed - Self.SCRIBBLE_AT) / Self.SCRIBBLE_FOR, 0), 1) } ?? 1
            let tip = ctx.crayon(scribble(b.r, b.c, g), BoxArt.crayon(owner), m.crayonW, CGFloat(p))
            if cap != nil && p > 0 && p < 1, let tip { pencils.append((tip, owner, 0.85)) }
        }

        // 2. Committed lines still springing from a straight capsule into the pinched dog-bone.
        if !lines.isEmpty {
            for r in 0...model.rows {
                for c in 0..<model.cols { if let o = model.hOwner[r][c] { drawEdge(ctx, BoxEdge(true, r, c), o, g, now) } }
            }
            for r in 0..<model.rows {
                for c in 0...model.cols { if let o = model.vOwner[r][c] { drawEdge(ctx, BoxEdge(false, r, c), o, g, now) } }
            }
        }

        // 3. The bot's pencil line.
        if let e = pending {
            let (ia, ib) = g.ends(e)
            let a = g.dot(pendingFromB ? ib : ia)
            let b = g.dot(pendingFromB ? ia : ib)
            let head = lerp(a, b, easeInOut((now - pendingStart) / pencilSeconds))
            ctx.growLine(a, head, m.growW, BoxArt.rival)
            pencils.append((head, .Rival, 1))
        }

        // 4. The player's live drag, or the line snapping back after a miss.
        if dragDot >= 0, let head = dragHead { ctx.growLine(g.dot(dragDot), head, m.growW, BoxArt.you) }
        let rt = (now - retractStart) / 0.16
        if retractDot >= 0 && rt < 1 {
            let home = g.dot(retractDot)
            ctx.growLine(home, lerp(retractFrom, home, 1 - (1 - rt) * (1 - rt)), m.growW, BoxArt.you)
        }

        // 5. Glow traces around boxes being captured.
        for cap in captures.values {
            let e = (now - cap.start) * speed
            if e > Self.GOLD_AT + 0.35 { continue }
            let p = min(max((e - Self.SCRIBBLE_AT) / Self.SCRIBBLE_FOR, 0), 1)
            let fade: Float = e < Self.GOLD_AT ? 1 : 1 - (e - Self.GOLD_AT) / 0.35
            ctx.glowTrace(g.dot(cap.r, cap.c), g.cell, BoxArt.glow(cap.owner), m.growW * 0.7, CGFloat(p), CGFloat(fade))
        }

        // 6. Dots: swell under the finger, spring back on release, flash gold on capture.
        for r in 0...model.rows {
            for c in 0...model.cols {
                let i = g.index(r, c)
                var scale: Float = 1
                if i == dragDot { scale = 1 + 0.45 * springStep(now - dragStart, 0.3, 0.5) }
                if i == hoverDot { scale = max(scale, 1 + 0.45 * springStep(now - hoverStart, 0.3, 0.5)) }
                if let t = pulses[i] {
                    let e = now - t
                    if i != dragDot && i != hoverDot && e < 1.2 { scale = 1 + 0.42 * (1 - springStep(e, 0.32, 0.38)) }
                }
                var gold: Float = 0
                if let t = golds[i] {
                    let e = (now - t) * speed
                    if e >= 0 && e < Self.GOLD_FOR {
                        // Snap to full gold, hold a beat, then fade back to slate.
                        if e < 0.07 { gold = e / 0.07 } else if e < 0.22 { gold = 1 } else { gold = 1 - (e - 0.22) / (Self.GOLD_FOR - 0.22) }
                        scale *= 1 + 0.34 * (1 - springStep(e, 0.3, 0.35)) * (e < 0.07 ? e / 0.07 : 1)
                        if e >= 0.07 { scale = max(scale, 1 + 0.3 * gold) }
                    }
                }
                ctx.flatDot(g.dot(r, c), m.dotR * CGFloat(scale), CGFloat(gold))
            }
        }

        // 7. Pencils over everything.
        for p in pencils { ctx.pencil(p.tip, m.pencilLen * p.k, p.owner) }
    }

    private func drawEdge(_ ctx: GraphicsContext, _ e: BoxEdge, _ owner: Player, _ g: BoardGeom, _ now: Float) {
        guard let anim = lines[e] else { return }
        let (ia, ib) = g.ends(e)
        let m = g.m
        let color = BoxArt.line(owner)
        let t = now - anim.start
        let a = g.dot(anim.fromB ? ib : ia)
        let b = g.dot(anim.fromB ? ia : ib)
        if t < anim.grow { ctx.growLine(a, lerp(a, b, easeInOut(t / anim.grow)), m.growW, color); return }
        let s = springStep((t - anim.grow) * speed, 0.36, 0.32)
        ctx.boneLine(a, b, lerp(m.growW, m.endW, s), lerp(m.growW, m.midW, s), color)
    }

    /// The "+1"s: pop at the box, then fly into the scorer's pill. Positions are in the play screen's
    /// coordinates (`boardRoot` is the board canvas origin there).
    func flyerFrames(_ now: Float, _ boardRoot: CGPoint, _ youPill: CGPoint, _ rivalPill: CGPoint, _ body: (CGPoint, CGFloat, Player) -> Void) {
        guard let g = geom else { return }
        for f in flyers {
            let e = (now - f.start) * speed
            if e < 0 || e > Self.FLY_FOR { continue }
            let bc = g.boxCenter(f.r, f.c)
            let from = CGPoint(x: boardRoot.x + bc.x, y: boardRoot.y + bc.y)
            let to = f.owner == .You ? youPill : rivalPill
            if e < 0.16 {
                body(from, CGFloat(1.25 * springStep(e, 0.22, 0.5)), f.owner)
            } else if e < 0.28 {
                body(from, 1, f.owner)
            } else {
                let t = min(max((e - 0.28) / (Self.FLY_FOR - 0.28), 0), 1)
                let k = t * t
                let p = lerp(from, to, k)
                body(CGPoint(x: p.x, y: p.y - CGFloat(sin(Float.pi * t)) * g.cell * 0.35), lerp(1, 0.55, t), f.owner)
            }
        }
    }
}
