import SwiftUI
import CoreGraphics

/// An sRGB colour usable by both SwiftUI and Core Graphics (Compose `Color` with `copy(alpha)`).
struct ArrowRGBA: Equatable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat

    init(_ rgb: UInt32, _ alpha: CGFloat = 1) {
        r = CGFloat((rgb >> 16) & 0xFF) / 255
        g = CGFloat((rgb >> 8) & 0xFF) / 255
        b = CGFloat(rgb & 0xFF) / 255
        a = alpha
    }

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    static let white = ArrowRGBA(0xFFFFFF)
    static let black = ArrowRGBA(0x000000)

    /// Compose `copy(alpha = x)`.
    func copy(alpha: CGFloat) -> ArrowRGBA { ArrowRGBA(r: r, g: g, b: b, a: min(max(alpha, 0), 1)) }
    var color: Color { Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a)) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// A board look: backdrop, arrow ink, dots and HUD colours.
final class ArrowTheme {
    let id: String
    let name: String
    let top: ArrowRGBA
    let bottom: ArrowRGBA
    let ink: [ArrowRGBA]
    let dots: ArrowRGBA
    /// Strength of the highlight stroke along each arrow (0 = flat).
    let gloss: CGFloat
    let isDark: Bool
    let hud: ArrowRGBA
    let glass: ArrowRGBA
    let stroke: ArrowRGBA

    init(_ id: String, _ name: String, _ top: ArrowRGBA, _ bottom: ArrowRGBA, _ ink: [ArrowRGBA], _ dots: ArrowRGBA,
         _ gloss: CGFloat, _ isDark: Bool, _ hud: ArrowRGBA, _ glass: ArrowRGBA, _ stroke: ArrowRGBA) {
        self.id = id
        self.name = name
        self.top = top
        self.bottom = bottom
        self.ink = ink
        self.dots = dots
        self.gloss = gloss
        self.isDark = isDark
        self.hud = hud
        self.glass = glass
        self.stroke = stroke
    }

    func color(_ arrow: Int) -> ArrowRGBA { ink[arrow % ink.count] }

    static let paper = ArrowTheme("paper", "Paper", ArrowRGBA(0xF7EFDF), ArrowRGBA(0xEFE3CB), [ArrowRGBA(0x5C4430)], ArrowRGBA(0x8C6F4E, 0.22),
                                  0.22, false, ArrowRGBA(0x5C4430), ArrowRGBA(0xFFFFFF, 0.75), ArrowRGBA(0x5C4430, 0.12))
    static let night = ArrowTheme(
        "night", "Night", ArrowRGBA(0x231C52), ArrowRGBA(0x14112E),
        [0xFF7A66, 0xFFC93A, 0x46D39A, 0x4F8DFF, 0xA67BFF, 0xFF5C93, 0x35C8F2].map { ArrowRGBA($0) },
        ArrowRGBA(0xFFFFFF, 0.12), 0.35, true, .white, ArrowRGBA(0xFFFFFF, 0.1), ArrowRGBA(0xFFFFFF, 0.16)
    )
    static let mint = ArrowTheme("mint", "Mint", ArrowRGBA(0xE3F7EF), ArrowRGBA(0xCDEFE4), [ArrowRGBA(0x1F5C4C), ArrowRGBA(0x2F8A6E)], ArrowRGBA(0x1F6B55, 0.2),
                                 0.25, false, ArrowRGBA(0x1F5C4C), ArrowRGBA(0xFFFFFF, 0.75), ArrowRGBA(0x1F5C4C, 0.12))
    static let ink = ArrowTheme("ink", "Ink", ArrowRGBA(0xFFFFFF), ArrowRGBA(0xF1F2F7), [ArrowRGBA(0x1C1E3A)], ArrowRGBA(0x1C1B29, 0.12),
                                0, false, ArrowRGBA(0x1C1E3A), ArrowRGBA(0xFFFFFF), ArrowRGBA(0x1C1E3A, 0.1))

    static let all = [night, ink, paper, mint]

    /// The player's choice, or Night in dark mode and Ink in light mode.
    static func resolve(_ id: String, _ dark: Bool) -> ArrowTheme { all.first { $0.id == id } ?? (dark ? night : ink) }

    static let crash = ArrowRGBA(0xFF4D5E)
    static let hint = ArrowRGBA(0x2FC58C)
}

/**
 * The snake slide: an arrow's body as a stretch of one long path made of its cells, carried on
 * past the head along its heading and back past the tail. Sliding by `s` cells moves the whole
 * body along that path, which is how an arrow leaves along its own shape.
 */
enum ArrowGeometry {
    /// Cell-space point at path position `t` (cell centres at whole numbers + 0.5).
    static func point(_ piece: ArrowPiece, _ t: Double) -> CGPoint {
        let cells = piece.cells
        let last = Double(cells.count - 1)
        if t >= last {
            let extra = t - last
            return CGPoint(x: Double(piece.head.c) + 0.5 + Double(piece.heading.dc) * extra,
                           y: Double(piece.head.r) + 0.5 + Double(piece.heading.dr) * extra)
        }
        if t <= 0 {
            let extra = -t
            return CGPoint(x: Double(piece.tail.c) + 0.5 + Double(piece.tailHeading.dc) * extra,
                           y: Double(piece.tail.r) + 0.5 + Double(piece.tailHeading.dr) * extra)
        }
        let i = Int(t)
        let f = t - Double(i)
        let a = cells[i]
        let b = cells[min(i + 1, cells.count - 1)]
        return CGPoint(x: Double(a.c) + 0.5 + Double(b.c - a.c) * f, y: Double(a.r) + 0.5 + Double(b.r - a.r) * f)
    }

    /// The body after sliding `s` cells (negative slides back behind the tail).
    static func body(_ piece: ArrowPiece, _ slide: Double) -> [CGPoint] {
        let length = Double(piece.cells.count - 1)
        var points: [CGPoint] = []
        points.reserveCapacity(piece.cells.count + 2)
        points.append(point(piece, slide))
        var k = slide.rounded(.down) + 1
        while k < slide + length {
            points.append(point(piece, k))
            k += 1
        }
        points.append(point(piece, slide + length))
        return points
    }

    /// Unit vector the head points along at the end of `points`.
    static func direction(_ points: [CGPoint], _ fallback: Heading) -> CGPoint {
        if points.count >= 2 {
            let a = points[points.count - 2]
            let b = points[points.count - 1]
            let len = hypot(b.x - a.x, b.y - a.y)
            if len > 0.001 { return CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len) }
        }
        return CGPoint(x: fallback.dc, y: fallback.dr)
    }
}

/// Draws arrows, into a Core Graphics context (the board's layers) or a SwiftUI `GraphicsContext`.
enum ArrowArt {
    struct Style {
        let color: ArrowRGBA
        let width: CGFloat
        let gloss: CGFloat
        var glow: ArrowRGBA? = nil
        var glowRadius: CGFloat = 0
        var opacity: CGFloat = 1

        init(_ color: ArrowRGBA, _ width: CGFloat, _ gloss: CGFloat, _ glow: ArrowRGBA? = nil, _ glowRadius: CGFloat = 0, _ opacity: CGFloat = 1) {
            self.color = color
            self.width = width
            self.gloss = gloss
            self.glow = glow
            self.glowRadius = glowRadius
            self.opacity = opacity
        }
    }

    /// Line thickness: in proportion to the cell on dense boards, but never chunky on small ones (points).
    static func bodyWidth(_ cell: CGFloat, _ theme: ArrowTheme, _ density: CGFloat = 1) -> CGFloat {
        min(max(1.2 * density, cell * (theme.isDark ? 0.3 : 0.27)), (theme.isDark ? 6 : 5.5) * density)
    }

    /// Android `BlurMaskFilter(radius)` blurs with σ ≈ 0.577·radius; a CG shadow's `blur` is about 2σ.
    static func cgBlur(_ radius: CGFloat) -> CGFloat { radius * 1.155 }
    /// … and a SwiftUI blur's radius is about σ.
    static func swiftUIBlur(_ radius: CGFloat) -> CGFloat { radius * 0.577 }

    struct Shapes {
        let body: CGPath
        let head: CGPath
        let bounds: CGRect
    }

    /// The body polyline and the arrowhead triangle for screen points (tail → head).
    static func shapes(_ points: [CGPoint], _ direction: CGPoint, _ cell: CGFloat, _ w: CGFloat) -> Shapes {
        let head = points[points.count - 1]
        let body = CGMutablePath()
        body.move(to: points[0])
        for i in 1..<points.count { body.addLine(to: points[i]) }
        let reach = min(cell * 0.78, w * 3.1)
        let back = min(cell * 0.12, w * 0.5)
        let half = min(cell * 0.5, w * 2.1)
        let tip = CGPoint(x: head.x + direction.x * reach, y: head.y + direction.y * reach)
        let base = CGPoint(x: head.x - direction.x * back, y: head.y - direction.y * back)
        let side = CGPoint(x: -direction.y * half, y: direction.x * half)
        let arrowHead = CGMutablePath()
        arrowHead.move(to: tip)
        arrowHead.addLine(to: CGPoint(x: base.x + side.x, y: base.y + side.y))
        arrowHead.addLine(to: CGPoint(x: base.x - side.x, y: base.y - side.y))
        arrowHead.closeSubpath()
        return Shapes(body: body, head: arrowHead, bounds: body.boundingBoxOfPath.union(arrowHead.boundingBoxOfPath))
    }

    // MARK: Core Graphics

    /// One arrow from screen-space body points (tail → head) and the head's direction.
    /// `shadowScale` converts points to the context's base space (1 in UIKit drawing, the pixel scale in raw bitmaps).
    static func drawArrow(_ ctx: CGContext, _ points: [CGPoint], _ direction: CGPoint, _ cell: CGFloat, _ style: Style, shadowScale: CGFloat = 1) {
        if points.isEmpty || style.opacity <= 0.003 { return }
        let w = style.width
        let s = shapes(points.count == 1 ? [points[0], points[0]] : points, direction, cell, w)
        let layered = style.opacity < 0.999
        ctx.saveGState()
        if layered {
            let glowPad = style.glow != nil ? style.glowRadius * 3 + w * 1.3 : 0
            ctx.clip(to: s.bounds.insetBy(dx: -(w * 2 + glowPad + 2), dy: -(w * 2 + glowPad + 2)))
            ctx.setAlpha(style.opacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if let glow = style.glow, style.glowRadius > 0 {
            // A blurred copy only: the shapes are drawn far away and their shadow lands here.
            let far: CGFloat = 20_000
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: far * shadowScale, height: 0), blur: cgBlur(style.glowRadius * 1.4) * shadowScale,
                          color: glow.copy(alpha: glow.a * 0.85).cg)
            ctx.translateBy(x: -far, y: 0)
            ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.setLineWidth(w * 2.6)
            // Body and head blur separately, like Android's two drawPath calls with the blur paint.
            ctx.addPath(s.body)
            ctx.strokePath()
            ctx.addPath(s.head)
            ctx.fillPath()
            ctx.restoreGState()
        }
        let c = style.color
        ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        ctx.setLineWidth(w)
        ctx.addPath(s.body)
        ctx.strokePath()
        ctx.addPath(s.head)
        ctx.fillPath()
        ctx.setLineWidth(w * 0.45)
        ctx.addPath(s.head)
        ctx.strokePath()
        if style.gloss > 0 && cell >= 5 {
            ctx.saveGState()
            ctx.translateBy(x: -w * 0.16, y: -w * 0.18)
            ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: style.gloss)
            ctx.setLineWidth(w * 0.28)
            ctx.addPath(s.body)
            ctx.strokePath()
            ctx.restoreGState()
        }
        if layered { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    /// A dotted lane from `from` along `direction` for `length` points.
    static func drawLane(_ ctx: CGContext, _ from: CGPoint, _ direction: CGPoint, _ length: CGFloat, _ cell: CGFloat, _ color: ArrowRGBA) {
        let to = CGPoint(x: from.x + direction.x * length, y: from.y + direction.y * length)
        let w = max(2, cell * 0.2)
        ctx.saveGState()
        ctx.setStrokeColor(red: color.r, green: color.g, blue: color.b, alpha: color.a)
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [0.1, max(6, cell * 0.7)])
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func fillCircle(_ ctx: CGContext, _ c: CGPoint, _ radius: CGFloat) {
        ctx.fillEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
    }

    // MARK: SwiftUI

    /// `drawArrow` for a SwiftUI `Canvas`.
    static func drawArrow(_ ctx: inout GraphicsContext, _ points: [CGPoint], _ direction: CGPoint, _ cell: CGFloat, _ style: Style) {
        if points.isEmpty || style.opacity <= 0.003 { return }
        let w = style.width
        let s = shapes(points.count == 1 ? [points[0], points[0]] : points, direction, cell, w)
        let body = Path(s.body)
        let head = Path(s.head)
        func paint(_ layer: inout GraphicsContext) {
            if let glow = style.glow, style.glowRadius > 0 {
                layer.drawLayer { g in
                    g.addFilter(.blur(radius: swiftUIBlur(style.glowRadius * 1.4)))
                    let gc = glow.copy(alpha: glow.a * 0.85).color
                    g.stroke(body, with: .color(gc), style: StrokeStyle(lineWidth: w * 2.6, lineCap: .round, lineJoin: .round))
                    g.fill(head, with: .color(gc))
                }
            }
            let color = style.color.color
            layer.stroke(body, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            layer.fill(head, with: .color(color))
            layer.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: w * 0.45, lineJoin: .round))
            if style.gloss > 0 && cell >= 5 {
                layer.stroke(body.offsetBy(dx: -w * 0.16, dy: -w * 0.18), with: .color(Color.white.opacity(Double(style.gloss))),
                             style: StrokeStyle(lineWidth: w * 0.28, lineCap: .round, lineJoin: .round))
            }
        }
        if style.opacity < 0.999 {
            // Kotlin `saveLayer` with the arrow's alpha, so overlapping strokes don't double up.
            ctx.drawLayer { layer in
                layer.opacity = Double(style.opacity)
                paint(&layer)
            }
        } else {
            paint(&ctx)
        }
    }
}
