import SwiftUI
import GameKit

/// Box Battle colours: sunny yellow (you) vs violet (rival) on a charcoal glass board.
enum BoxArt {
    // A charcoal glass board with a soft grey rim, so the coloured lines glow.
    static let boardTop = hex(0x26272E)
    static let boardBottom = hex(0x16171C)
    static let rimTop = hex(0x9A9DAA)
    static let rimBottom = hex(0x555866)
    static let rimGlow = hex(0x8E929F)
    static let dotTop = hex(0xF4F5F8)
    static let dotBottom = hex(0xA7AAB6)
    /// Capture highlight (corners, dot flash): a warm orange, distinct from the yellow player.
    static let gold = hex(0xFF8A3D)
    static let goldDeep = hex(0xD9661C)

    // Player colours: sunny yellow for you, violet for the rival.
    static let you = hex(0xFFD23F)
    static let rival = hex(0xA970FF)

    private static let youCrayon = hex(0xFFC21A)
    private static let rivalCrayon = hex(0x9A5CFF)
    private static let youGlow = hex(0xFFE88A)
    private static let rivalGlow = hex(0xD2B6FF)
    private static let youPencil = [hex(0xFFE27A), hex(0xE0A400)]
    private static let rivalPencil = [hex(0xC9A6FF), hex(0x7A3FE0)]

    static func line(_ p: Player) -> Color { p == .You ? you : rival }
    static func crayon(_ p: Player) -> Color { p == .You ? youCrayon : rivalCrayon }
    static func glow(_ p: Player) -> Color { p == .You ? youGlow : rivalGlow }
    static func pencil(_ p: Player) -> [Color] { p == .You ? youPencil : rivalPencil }
    /// The 3D key faces used for each player's HUD pieces.
    static func key(_ p: Player) -> [Color] { p == .You ? youPencil : rivalPencil }

    // MARK: Pre-built shadings (no per-frame colour maths)

    /// `dotTop.mix(gold, g)` → `dotBottom.mix(goldDeep, g)` gradients for g = 0, 1/64 … 1.
    fileprivate static let dotGradients: [Gradient] = (0...64).map { i in
        let g = Double(i) / 64
        return Gradient(colors: [dotTop.mix(gold, g), dotBottom.mix(goldDeep, g)])
    }

    fileprivate static func dotGradient(_ gold: CGFloat) -> Gradient {
        dotGradients[Int((min(max(gold, 0), 1) * 64).rounded())]
    }

    fileprivate static let youPencilGradient = Gradient(colors: youPencil)
    fileprivate static let rivalPencilGradient = Gradient(colors: rivalPencil)
    fileprivate static let youPencilShade = youPencil[1].mix(.black, 0.18).copy(alpha: 0.5)
    fileprivate static let rivalPencilShade = rivalPencil[1].mix(.black, 0.18).copy(alpha: 0.5)
    fileprivate static let woodGradient = Gradient(colors: [hex(0xF8DDB0), hex(0xE0AF72)])
    fileprivate static let ferruleGradient = Gradient(colors: [hex(0xD5D9E1), hex(0x8C92A0)])
    fileprivate static let eraserGradient = Gradient(colors: [hex(0x5E6475), hex(0x383D4B)])
    fileprivate static let rimGradient = Gradient(colors: [rimTop, rimBottom])
    fileprivate static let boardGradient = Gradient(colors: [boardTop, boardBottom])
    fileprivate static let sheenGradient = Gradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0)])
}

/// Sizes for one board, all derived from the dot spacing.
struct BoxMetrics {
    let dotR: CGFloat
    let endW: CGFloat
    let midW: CGFloat
    let growW: CGFloat
    let pencilLen: CGFloat
    let crayonW: CGFloat

    init(_ cell: CGFloat, _ side: CGFloat) {
        dotR = max(cell * 0.1, side * 0.017)
        endW = dotR * 1.9
        midW = endW * 0.6
        growW = endW * 0.74
        pencilLen = max(cell * 0.72, side * 0.17)
        crayonW = max(cell * 0.078, side * 0.013)
    }
}

/// Android `BlurMaskFilter(radius)` blurs with sigma = 0.57735·radius + 0.5 px; SwiftUI's blur radius is a
/// sigma in points (the Android reference phone has 2 px per dp).
@inline(__always)
func boxBlurSigma(_ radius: CGFloat) -> CGFloat { 0.57735 * radius + 0.25 }

@inline(__always)
fileprivate func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

@inline(__always)
fileprivate func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
    var p = Path()
    p.move(to: a)
    p.addLine(to: b)
    return p
}

private let roundStroke = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)

@inline(__always)
fileprivate func rounds(_ width: CGFloat) -> StrokeStyle {
    var s = roundStroke
    s.lineWidth = width
    return s
}

extension GraphicsContext {
    /// A flat slate dot; `gold` (0..1) flashes it gold with a soft halo.
    func flatDot(_ c: CGPoint, _ r: CGFloat, _ gold: CGFloat = 0) {
        if gold > 0 { fill(circle(c, r * 1.8), with: .color(BoxArt.gold.opacity(Double(0.38 * gold)))) }
        fill(circle(c, r), with: .linearGradient(BoxArt.dotGradient(gold), startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
        fill(circle(CGPoint(x: c.x - r * 0.32, y: c.y - r * 0.36), r * 0.36), with: .color(Color.white.opacity(Double(0.16 + 0.2 * gold))))
    }

    /// A soft neon halo along `path` (a blurred stroke), drawn under the line itself.
    func neonHalo(_ path: Path, _ color: Color, _ width: CGFloat, _ alpha: Double = 0.75) {
        let blur = max(width * 0.32, 0.5)
        drawLayer { l in
            l.addFilter(.blur(radius: boxBlurSigma(blur)))
            l.stroke(path, with: .color(color.opacity(alpha)), style: rounds(width))
        }
    }

    /// A straight neon capsule — the line while it is being drawn.
    func growLine(_ a: CGPoint, _ head: CGPoint, _ width: CGFloat, _ color: Color) {
        if hypot(head.x - a.x, head.y - a.y) < 0.25 {
            fill(circle(a, width), with: .color(color.opacity(0.35)))
            fill(circle(a, width / 2), with: .color(color))
            return
        }
        let seg = segment(a, head)
        neonHalo(seg, color, width * 1.7)
        stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        stroke(seg, with: .color(Color.white.opacity(0.85)), style: StrokeStyle(lineWidth: width * 0.32, lineCap: .round))
    }

    /// The settled "dog-bone" line: thick at both dots, pinched in the middle. `halo: false` skips the
    /// glow (callers that batch every glow into one blurred layer draw it with `boneHalo`).
    func boneLine(_ a: CGPoint, _ b: CGPoint, _ endW: CGFloat, _ midW: CGFloat, _ color: Color, halo: Bool = true) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = hypot(dx, dy)
        if len < 0.5 { return }
        let nx = -dy / len
        let ny = dx / len
        let re = endW / 2
        let k = midW - re // control offset so the curve's midpoint sits at midW / 2
        let mx = (a.x + b.x) / 2
        let my = (a.y + b.y) / 2
        var p = Path()
        p.move(to: CGPoint(x: a.x + nx * re, y: a.y + ny * re))
        p.addQuadCurve(to: CGPoint(x: b.x + nx * re, y: b.y + ny * re), control: CGPoint(x: mx + nx * k, y: my + ny * k))
        p.addLine(to: CGPoint(x: b.x - nx * re, y: b.y - ny * re))
        p.addQuadCurve(to: CGPoint(x: a.x - nx * re, y: a.y - ny * re), control: CGPoint(x: mx - nx * k, y: my - ny * k))
        p.closeSubpath()
        let ux = dx / len
        let uy = dy / len
        if halo { neonHalo(segment(a, b), color, endW * 1.45) }
        fill(p, with: .color(color))
        fill(circle(a, re), with: .color(color))
        fill(circle(b, re), with: .color(color))
        // Hot white core running down the tube.
        let inset = re * 0.9
        stroke(segment(CGPoint(x: a.x + ux * inset, y: a.y + uy * inset), CGPoint(x: b.x - ux * inset, y: b.y - uy * inset)),
               with: .color(Color.white.opacity(0.82)), style: StrokeStyle(lineWidth: midW * 0.34, lineCap: .round))
    }

    /// A 3D colouring pencil with its lead tip at `tip`, body leaning up and to the right.
    func pencil(_ tip: CGPoint, _ length: CGFloat, _ owner: Player, _ angle: Double = -32) {
        let l = length
        let w = l * 0.15
        let x = tip.x
        let y = tip.y
        var g = self
        g.translateBy(x: x, y: y)
        g.rotate(by: .degrees(angle))
        g.translateBy(x: -x, y: -y)
        let colors = BoxArt.pencil(owner)
        let top = y - w / 2
        let bottom = y + w / 2
        // Soft shadow under the body.
        g.fill(Path(roundedRect: CGRect(x: x + l * 0.12 + w * 0.2, y: y - w / 2 + w * 0.45, width: l * 0.88, height: w), cornerRadius: w / 2),
               with: .color(Color.black.opacity(0.16)))
        // Wooden cone and lead.
        var wood = Path()
        wood.move(to: CGPoint(x: x + l * 0.05, y: y - w * 0.15))
        wood.addLine(to: CGPoint(x: x + l * 0.21, y: y - w / 2))
        wood.addLine(to: CGPoint(x: x + l * 0.21, y: y + w / 2))
        wood.addLine(to: CGPoint(x: x + l * 0.05, y: y + w * 0.15))
        wood.closeSubpath()
        g.fill(wood, with: .linearGradient(BoxArt.woodGradient, startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: bottom)))
        var lead = Path()
        lead.move(to: CGPoint(x: x, y: y))
        lead.addLine(to: CGPoint(x: x + l * 0.075, y: y - w * 0.2))
        lead.addLine(to: CGPoint(x: x + l * 0.075, y: y + w * 0.2))
        lead.closeSubpath()
        g.fill(lead, with: .color(colors[1]))
        // Body, with a lighter facet along the top.
        g.fill(Path(CGRect(x: x + l * 0.2, y: top, width: l * 0.65, height: w)),
               with: .linearGradient(owner == .You ? BoxArt.youPencilGradient : BoxArt.rivalPencilGradient,
                                     startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: bottom)))
        g.fill(Path(CGRect(x: x + l * 0.2, y: y - w * 0.36, width: l * 0.65, height: w * 0.18)), with: .color(Color.white.opacity(0.28)))
        g.fill(Path(CGRect(x: x + l * 0.2, y: y + w * 0.22, width: l * 0.65, height: w * 0.28)),
               with: .color(owner == .You ? BoxArt.youPencilShade : BoxArt.rivalPencilShade))
        // Metal ferrule and eraser cap.
        g.fill(Path(CGRect(x: x + l * 0.85, y: top, width: l * 0.06, height: w)),
               with: .linearGradient(BoxArt.ferruleGradient, startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: bottom)))
        g.fill(Path(roundedRect: CGRect(x: x + l * 0.9, y: top, width: l * 0.1, height: w), cornerRadius: w * 0.32),
               with: .linearGradient(BoxArt.eraserGradient, startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: bottom)))
    }

    /// Draws the first `progress` of a scribble in waxy crayon strokes and returns where the crayon
    /// tip is (for the pencil to follow). `halo: false` leaves the glow to a batched layer.
    @discardableResult
    func crayon(_ path: Path, _ color: Color, _ width: CGFloat, _ progress: CGFloat, halo: Bool = true) -> CGPoint? {
        if progress <= 0 { return nil }
        let seg = progress >= 1 ? path : path.trimmedPath(from: 0, to: progress)
        let style = rounds(width)
        if halo { neonHalo(seg, color, width * 2.2, 0.65) }
        stroke(seg, with: .color(color), style: style)
        var g = self
        g.translateBy(x: width * 0.2, y: -width * 0.15)
        g.stroke(seg, with: .color(Color.white.opacity(0.6)), style: rounds(width * 0.32))
        return seg.currentPoint
    }

    /// A glowing trace around a box's four sides, drawn up to `progress`, faded by `alpha`.
    func glowTrace(_ tl: CGPoint, _ cell: CGFloat, _ color: Color, _ width: CGFloat, _ progress: CGFloat, _ alpha: CGFloat) {
        if progress <= 0 || alpha <= 0 { return }
        var path = Path()
        path.move(to: tl)
        path.addLine(to: CGPoint(x: tl.x + cell, y: tl.y))
        path.addLine(to: CGPoint(x: tl.x + cell, y: tl.y + cell))
        path.addLine(to: CGPoint(x: tl.x, y: tl.y + cell))
        path.closeSubpath()
        let seg = progress >= 1 ? path : path.trimmedPath(from: 0, to: progress)
        let a = Double(alpha)
        stroke(seg, with: .color(color.opacity(0.28 * a)), style: rounds(width * 2.2))
        stroke(seg, with: .color(color.opacity(0.9 * a)), style: rounds(width * 1.05))
        stroke(seg, with: .color(Color.white.opacity(0.85 * a)), style: rounds(width * 0.38))
    }

    /// The charcoal glass board with a softly glowing grey rim.
    func boardCard(_ rect: CGRect, _ corner: CGFloat) {
        let glow = Path(roundedRect: rect, cornerRadius: corner)
        neonHalo(glow, BoxArt.rimGlow, min(rect.width, rect.height) * 0.05, 0.55)
        fill(glow, with: .linearGradient(BoxArt.rimGradient, startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
        let inset = min(rect.width, rect.height) * 0.022
        let inner = rect.insetBy(dx: inset, dy: inset)
        fill(Path(roundedRect: inner, cornerRadius: corner * 0.86),
             with: .linearGradient(BoxArt.boardGradient, startPoint: CGPoint(x: inner.minX, y: inner.minY), endPoint: CGPoint(x: inner.minX, y: inner.maxY)))
        // A soft light sheen across the top of the glass.
        fill(Path(roundedRect: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * 0.45), cornerRadius: corner * 0.86),
             with: .linearGradient(BoxArt.sheenGradient, startPoint: CGPoint(x: inner.minX, y: inner.minY),
                                   endPoint: CGPoint(x: inner.minX, y: inner.minY + inner.height * 0.45)))
    }
}

/// The points of a hand-drawn zig-zag that fills a claimed box, stable for a given `seed`
/// (Kotlin `scribblePath`'s point loop, bit for bit: Float maths and `kotlin.random.Random(seed)`).
func scribblePoints(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ seed: Int) -> [(x: Float, y: Float)] {
    let width = right - left
    let height = bottom - top
    let rnd = KotlinRandom(intSeed: seed)
    let n = 6
    var pts: [(x: Float, y: Float)] = []
    pts.reserveCapacity(n + 1)
    for i in 0...n {
        let k = Float(i / 2)
        let up = i % 2 == 1
        // A quick crayon "/|/|/|": slanted up-strokes, near-vertical down-strokes, uneven peaks.
        let u: Float = (up ? Float(0.27) * k + Float(0.25) : Float(0.27) * k - (k > 0 ? Float(0.03) : Float(0))) / Float(0.79)
        let x: Float = left + width * u + (rnd.nextFloat() - Float(0.5)) * width * Float(0.04)
        let y: Float = up ? top + height * rnd.nextFloat() * Float(0.16) : bottom - height * rnd.nextFloat() * Float(0.12)
        pts.append((x, y))
    }
    return pts
}

/// A hand-drawn zig-zag that fills a claimed box, stable for a given `seed`.
func scribblePath(_ rect: CGRect, _ seed: Int) -> Path {
    let pts = scribblePoints(Float(rect.minX), Float(rect.minY), Float(rect.maxX), Float(rect.maxY), seed)
        .map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    let n = pts.count - 1
    // A polyline with softly rounded tips that keeps the full stroke height.
    var path = Path()
    path.move(to: pts[0])
    for i in 1..<n {
        let p = pts[i]
        let a = CGPoint(x: p.x + (pts[i - 1].x - p.x) * 0.2, y: p.y + (pts[i - 1].y - p.y) * 0.2)
        let b = CGPoint(x: p.x + (pts[i + 1].x - p.x) * 0.2, y: p.y + (pts[i + 1].y - p.y) * 0.2)
        path.addLine(to: a)
        path.addQuadCurve(to: b, control: p)
    }
    path.addLine(to: pts[n])
    return path
}
