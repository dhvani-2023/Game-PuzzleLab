import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import CoreText
import GameKit

/// One cached bitmap: the CGImage plus a SwiftUI `Image` of it (scale 1: one point per pixel, for the
/// pixel-space scene canvas).
final class TileSprite {
    let cg: CGImage
    let image: Image
    var width: Int { cg.width }
    var height: Int { cg.height }

    init(_ cg: CGImage) {
        self.cg = cg
        image = Image(decorative: cg, scale: 1)
    }

    /// The same bitmap for a SwiftUI view, at the screen scale.
    func image(scale: CGFloat) -> Image { Image(decorative: cg, scale: scale) }
}

/// A pre-rendered outlined label (scene text): the outline and the fill as two bitmaps (Android draws
/// them as two text layouts, each with the label's alpha). `width`×`height` is the text's layout box,
/// `pad` the extra margin the outline needs on each side of it.
final class TileLabel {
    let outline: TileSprite
    let inner: TileSprite
    let width: CGFloat
    let height: CGFloat
    let pad: CGFloat

    init(outline: TileSprite, inner: TileSprite, width: CGFloat, height: CGFloat, pad: CGFloat) {
        self.outline = outline
        self.inner = inner
        self.width = width
        self.height = height
        self.pad = pad
    }
}

/**
 * Every Tile Burst bitmap, painted at runtime and cached (a port of the Android `TileArt`, itself a port
 * of the iOS Core Graphics one). Everything is painted y-down in pixels, exactly like the Android canvas
 * code; effect textures get a 3× supersample because they are stretched on screen.
 */
enum TileArt {
    /** Ruby, Tangerine, Honey, Lime, Aqua, Cobalt, Grape. */
    static let tones: [Int] = [0xF2445A, 0xFF8C2E, 0xFFC93A, 0x56D364, 0x35C8F2, 0x3F6BF0, 0xA45CF0]

    private static var cache: [String: TileSprite] = [:]
    private static let lock = NSLock()
    /// Supersampling for the small effect textures (glow, sparkle, ring, beam…).
    private static let fx: CGFloat = 3

    // MARK: Colour helpers

    static func argb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: min(max(a, 0), 1))
    }

    /// Kotlin `mix(a, b, t)`: per-channel RGB lerp, rounded.
    static func mix(_ a: Int, _ b: Int, _ t: Float) -> Int {
        func ch(_ v: Int, _ s: Int) -> Float { Float((v >> s) & 255) }
        func m(_ s: Int) -> Int { Kt.roundToInt(ch(a, s) * (1 - t) + ch(b, s) * t).coerceIn(0, 255) }
        return (m(16) << 16) | (m(8) << 8) | m(0)
    }

    static func color(_ hex: Int, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: a)
    }

    // MARK: Bitmaps

    private static func cached(_ key: String, _ w: Int, _ h: Int, scale: CGFloat = 1, _ draw: (CGContext) -> Void) -> TileSprite {
        lock.lock()
        defer { lock.unlock() }
        if let s = cache[key] { return s }
        let s = TileSprite(render(w, h, scale: scale, draw))
        cache[key] = s
        return s
    }

    /// A transparent `w`×`h` bitmap (times `scale`), drawn y-down in `w`×`h` units.
    static func render(_ w: Int, _ h: Int, scale: CGFloat = 1, _ draw: (CGContext) -> Void) -> CGImage {
        let pw = max(1, Int((CGFloat(w) * scale).rounded()))
        let ph = max(1, Int((CGFloat(h) * scale).rounded()))
        let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()!
    }

    /// Compose `ColorFilter.tint(color, BlendMode.Modulate)` baked in: every premultiplied channel × tint.
    private static func tinted(_ base: CGImage, _ r: Double, _ g: Double, _ b: Double) -> CGImage {
        let w = base.width, h = base.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let data = ctx.data {
            let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
            let tr = UInt32((r * 256).rounded()), tg = UInt32((g * 256).rounded()), tb = UInt32((b * 256).rounded())
            for i in stride(from: 0, to: w * h * 4, by: 4) {
                p[i] = UInt8(min(255, (UInt32(p[i]) * tr) >> 8))
                p[i + 1] = UInt8(min(255, (UInt32(p[i + 1]) * tg) >> 8))
                p[i + 2] = UInt8(min(255, (UInt32(p[i + 2]) * tb) >> 8))
            }
        }
        return ctx.makeImage()!
    }

    /// `sprite` tinted by `tint` (cached per colour).
    static func tint(_ name: String, _ base: TileSprite, _ tint: Color) -> TileSprite {
        let c = tint.rgba
        let key = "\(name)#\(Int(c.r * 255))_\(Int(c.g * 255))_\(Int(c.b * 255))"
        lock.lock()
        defer { lock.unlock() }
        if let s = cache[key] { return s }
        let s = TileSprite(tinted(base.cg, c.r, c.g, c.b))
        cache[key] = s
        return s
    }

    private static func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        let rad = max(0, min(radius, r.width / 2, r.height / 2))
        return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
    }

    private static func gradient(_ colors: [CGColor], _ stops: [CGFloat]? = nil) -> CGGradient {
        let locs = stops ?? (colors.count == 1 ? [0] : (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) })
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locs)!
    }

    private static let clamp: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

    /// Fills the current clip with a vertical/horizontal linear gradient from (x0, y0) to (x1, y1).
    private static func linear(_ c: CGContext, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ colors: [CGColor], _ stops: [CGFloat]? = nil) {
        c.drawLinearGradient(gradient(colors, stops), start: CGPoint(x: x0, y: y0), end: CGPoint(x: x1, y: y1), options: clamp)
    }

    private static func radial(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ colors: [CGColor], _ stops: [CGFloat]? = nil) {
        let p = CGPoint(x: cx, y: cy)
        c.drawRadialGradient(gradient(colors, stops), startCenter: p, startRadius: 0, endCenter: p, endRadius: max(0.01, r), options: clamp)
    }

    private static func fill(_ c: CGContext, _ path: CGPath, _ color: CGColor) {
        c.addPath(path)
        c.setFillColor(color)
        c.fillPath()
    }

    private static func polygon(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts)
        p.closeSubpath()
        return p
    }

    /// Android `setShadowLayer(radius, 0, dy, color)` (Skia sigma ≈ 0.577·radius + 0.5; Quartz blur ≈ 2σ).
    private static func shadow(_ c: CGContext, _ radius: CGFloat, _ dy: CGFloat, _ color: CGColor) {
        let scale = abs(c.ctm.a)
        c.setShadow(offset: CGSize(width: 0, height: -dy * scale), blur: 2 * (0.57735 * radius + 0.5) * scale, color: color)
    }

    // MARK: Blocks

    /** A glossy bevelled jewel block filling `r`. */
    static func paintBlock(_ c: CGContext, _ r: CGRect, _ base: Int) {
        let bevel = r.width * 0.14
        let light = mix(base, 0xFFFFFF, 0.42)
        let lighter = mix(base, 0xFFFFFF, 0.62)
        let dark = mix(base, 0x10061F, 0.32)
        let darker = mix(base, 0x10061F, 0.5)
        c.saveGState()
        c.addPath(rr(r, r.width * 0.13))
        c.clip()
        let i = r.insetBy(dx: bevel, dy: bevel)
        func facet(_ color: Int, _ pts: [CGFloat]) {
            var ps: [CGPoint] = []
            var k = 0
            while k < pts.count { ps.append(CGPoint(x: pts[k], y: pts[k + 1])); k += 2 }
            fill(c, polygon(ps), argb(color))
        }
        facet(lighter, [r.minX, r.minY, r.maxX, r.minY, i.maxX, i.minY, i.minX, i.minY])
        facet(light, [r.minX, r.minY, r.minX, r.maxY, i.minX, i.maxY, i.minX, i.minY])
        facet(dark, [r.maxX, r.minY, r.maxX, r.maxY, i.maxX, i.maxY, i.maxX, i.minY])
        facet(darker, [r.minX, r.maxY, r.maxX, r.maxY, i.maxX, i.maxY, i.minX, i.maxY])
        c.addPath(rr(i, r.width * 0.05))
        c.clip()
        linear(c, 0, i.minY, 0, i.maxY, [argb(mix(base, 0xFFFFFF, 0.12)), argb(mix(base, 0x10061F, 0.1))])
        let hx = i.midX - i.width * 0.12
        let hy = i.midY - i.height * 0.14
        radial(c, hx, hy, i.width * 0.72, [argb(0xFFFFFF, 0.3), argb(0xFFFFFF, 0)])
        let gloss = CGRect(x: i.minX + i.width * 0.12, y: i.minY + i.height * 0.12, width: i.width * 0.38, height: i.height * 0.1)
        fill(c, rr(gloss, i.height * 0.05), argb(0xFFFFFF, 0.6))
        c.restoreGState()
    }

    /** One block, `size` px square, with a hairline gap so neighbours read as separate. */
    static func block(_ tone: Int, _ size: Int) -> TileSprite {
        cached("block\(tone)_\(size)", size, size) { c in
            let inset = CGFloat(size) * 0.035
            paintBlock(c, CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2), tones[Kt.mod(tone, tones.count)])
        }
    }

    /** White rounded outline for the drop preview. */
    static func outline(_ size: Int) -> TileSprite {
        cached("outline_\(size)", size, size) { c in
            let s = CGFloat(size)
            let inset = s * 0.06
            c.addPath(rr(CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2), s * 0.14))
            c.setLineWidth(max(2, s * 0.05))
            c.setStrokeColor(argb(0xFFFFFF, 0.9))
            c.strokePath()
        }
    }

    /// Kotlin `drawRoundRectCentered(c, side, color, cell * 0.12)` as a sprite: a `0.93·size` square with
    /// corner `0.12·size`, drawn at `cell · scale · 0.93` with the colour's alpha as opacity.
    static func roundSquare(_ size: Int, _ rgb: Int) -> TileSprite {
        let side = Int((CGFloat(size) * 0.93).rounded())
        return cached("square\(rgb)_\(size)", side, side) { c in
            fill(c, rr(CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)), CGFloat(size) * 0.12), argb(rgb))
        }
    }

    // MARK: Gems

    static func paintGem(_ c: CGContext, _ gem: TileGem, _ r: CGRect) {
        let cx = r.midX
        let cy = r.midY
        let R = r.width / 2
        let shade = argb(0x1A0830, 0.5)
        switch gem {
        case .Star:
            var pts: [CGPoint] = []
            for k in 0..<10 {
                let a = -Double.pi / 2 + Double(k) * Double.pi / 5
                let rr = k % 2 == 0 ? R : R * 0.46
                pts.append(CGPoint(x: cx + CGFloat(cos(a)) * rr, y: cy + CGFloat(sin(a)) * rr))
            }
            let path = polygon(pts)
            c.saveGState()
            shadow(c, R * 0.18, R * 0.08, shade)
            fill(c, path, argb(0xFFB21E))
            c.restoreGState()
            c.saveGState()
            c.addPath(path)
            c.clip()
            linear(c, cx, cy - R, cx, cy + R, [argb(0xFFF2A8), argb(0xFFC93A), argb(0xF08A12)], [0, 0.45, 1])
            c.restoreGState()
            c.addPath(path)
            c.setLineWidth(R * 0.07)
            c.setLineJoin(.round)
            c.setStrokeColor(argb(0xFFFFFF, 0.8))
            c.strokePath()
        case .Ruby:
            let pts: [CGPoint] = (0..<6).map { k in
                let a = -(Double(k) * Double.pi / 3 + Double.pi / 6)
                return CGPoint(x: cx + CGFloat(cos(a)) * R * 0.95, y: cy + CGFloat(sin(a)) * R * 0.95)
            }
            let hexPath = polygon(pts)
            c.saveGState()
            shadow(c, R * 0.18, R * 0.08, shade)
            fill(c, hexPath, argb(0xC4123A))
            c.restoreGState()
            let inner = pts.map { CGPoint(x: cx + ($0.x - cx) * 0.52, y: cy + ($0.y - cy) * 0.52) }
            let faceColors = [0xFF5A7A, 0xFF3D63, 0xE01E4A, 0xB50E35, 0xD0193F, 0xFF7090]
            for k in 0..<6 {
                fill(c, polygon([pts[k], pts[(k + 1) % 6], inner[(k + 1) % 6], inner[k]]), argb(faceColors[k]))
            }
            fill(c, polygon(inner), argb(0xFF8FA6))
            c.setFillColor(argb(0xFFFFFF, 0.75))
            c.fillEllipse(in: CGRect(x: cx - R * 0.3, y: cy - R * 0.23, width: R * 0.26, height: R * 0.18))
        case .Diamond:
            let top = cy - R * 0.55
            let girdle = cy - R * 0.2
            let bottom = cy + R * 0.95
            let outlinePath = polygon([CGPoint(x: cx - R * 0.55, y: top), CGPoint(x: cx + R * 0.55, y: top), CGPoint(x: cx + R * 0.98, y: girdle),
                                       CGPoint(x: cx, y: bottom), CGPoint(x: cx - R * 0.98, y: girdle)])
            c.saveGState()
            shadow(c, R * 0.18, R * 0.08, shade)
            fill(c, outlinePath, argb(0x1FA8E0))
            c.restoreGState()
            func f(_ color: Int, _ p: [CGFloat]) {
                var ps: [CGPoint] = []
                var k = 0
                while k < p.count { ps.append(CGPoint(x: p[k], y: p[k + 1])); k += 2 }
                fill(c, polygon(ps), argb(color))
            }
            f(0xBDF3FF, [cx - R * 0.55, top, cx + R * 0.55, top, cx + R * 0.3, girdle, cx - R * 0.3, girdle])
            f(0x7FDDFF, [cx - R * 0.55, top, cx - R * 0.3, girdle, cx - R * 0.98, girdle])
            f(0x4CC4F5, [cx + R * 0.55, top, cx + R * 0.98, girdle, cx + R * 0.3, girdle])
            f(0x38B6EE, [cx - R * 0.98, girdle, cx - R * 0.3, girdle, cx, bottom])
            f(0x8BE4FF, [cx - R * 0.3, girdle, cx + R * 0.3, girdle, cx, bottom])
            f(0x169BD6, [cx + R * 0.3, girdle, cx + R * 0.98, girdle, cx, bottom])
            c.addPath(outlinePath)
            c.setLineWidth(R * 0.06)
            c.setLineJoin(.round)
            c.setStrokeColor(argb(0xFFFFFF, 0.85))
            c.strokePath()
        }
    }

    static func gem(_ gem: TileGem, _ size: Int) -> TileSprite {
        cached("gem\(gem.ordinal)_\(size)", size, size) { c in
            let inset = CGFloat(size) * 0.08
            paintGem(c, gem, CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2))
        }
    }

    // MARK: Board

    static func boardMargin(_ cell: Float) -> Float { Float(Kt.roundToInt(cell * 0.32)) }

    /** Board frame plus recessed wells. `fever` swaps to a warm gold frame. */
    static func board(_ cell: Int, _ fever: Bool) -> TileSprite {
        let margin = CGFloat(boardMargin(Float(cell)))
        let side = Kt.roundToInt(Float(CGFloat(cell) * 8 + margin * 2))
        return cached("board\(fever)_\(cell)", side, side) { c in
            let s = CGFloat(side)
            let cellF = CGFloat(cell)
            c.saveGState()
            c.addPath(rr(CGRect(x: 2, y: 2, width: s - 4, height: s - 4), margin * 1.4))
            c.clip()
            linear(c, 0, 0, 0, s, fever ? [argb(0xFFE28A), argb(0xFF9F2E)] : [argb(0x8E7CFF, 0.9), argb(0x5A49D6, 0.9)])
            c.restoreGState()
            fill(c, rr(CGRect(x: margin * 0.5, y: margin * 0.5, width: s - margin, height: s - margin), margin), argb(fever ? 0x3A1C0A : 0x17134A))
            for r in 0..<8 {
                for col in 0..<8 {
                    let well = CGRect(x: margin + CGFloat(col) * cellF, y: margin + CGFloat(r) * cellF, width: cellF, height: cellF)
                        .insetBy(dx: cellF * 0.05, dy: cellF * 0.05)
                    c.saveGState()
                    c.addPath(rr(well, cellF * 0.14))
                    c.clip()
                    let base = fever ? ((r + col) % 2 == 0 ? 0x5A2E12 : 0x51290F) : ((r + col) % 2 == 0 ? 0x252070 : 0x221D68)
                    c.setFillColor(argb(base))
                    c.fill(well)
                    linear(c, 0, well.minY, 0, well.minY + cellF * 0.2, [argb(0, 0.35), argb(0, 0)])
                    c.restoreGState()
                }
            }
        }
    }

    // MARK: Effects

    static let glow: TileSprite = {
        cached("glow", 64, 64, scale: fx) { c in
            c.addEllipse(in: CGRect(x: 0, y: 0, width: 64, height: 64))
            c.clip()
            radial(c, 32, 32, 32, [argb(0xFFFFFF, 0.95), argb(0xFFFFFF, 0.35), argb(0xFFFFFF, 0)], [0, 0.35, 1])
        }
    }()

    static let sparkle: TileSprite = {
        cached("sparkle", 48, 48, scale: fx) { c in
            c.saveGState()
            c.addEllipse(in: CGRect(x: 10, y: 10, width: 28, height: 28))
            c.clip()
            radial(c, 24, 24, 14, [argb(0xFFFFFF, 0.6), argb(0xFFFFFF, 0)])
            c.restoreGState()
            var pts: [CGPoint] = []
            for k in 0..<8 {
                let a = Double(k) * Double.pi / 4
                let r: CGFloat = k % 2 == 0 ? 23 : 4
                pts.append(CGPoint(x: 24 + CGFloat(cos(a)) * r, y: 24 + CGFloat(sin(a)) * r))
            }
            fill(c, polygon(pts), argb(0xFFFFFF))
        }
    }()

    /** A small square shard with a bevel highlight; tinted per block when drawn. */
    static let shard: TileSprite = {
        cached("shard", 40, 40, scale: fx) { c in paintBlock(c, CGRect(x: 2, y: 2, width: 36, height: 36), 0xD8D8E8) }
    }()

    static let ring: TileSprite = {
        cached("ring", 128, 128, scale: fx) { c in
            let r = CGRect(x: 10, y: 10, width: 108, height: 108)
            c.setLineWidth(14)
            c.setStrokeColor(argb(0xFFFFFF, 0.35))
            c.strokeEllipse(in: r)
            c.setLineWidth(5)
            c.setStrokeColor(argb(0xFFFFFF, 0.95))
            c.strokeEllipse(in: r)
        }
    }()

    /** A horizontal light beam; stretched along a row or rotated for a column. */
    static let beam: TileSprite = {
        cached("beam", 256, 48, scale: fx) { c in
            linear(c, 0, 0, 0, 48, [argb(0xFFFFFF, 0), argb(0xFFFFFF, 0.6), argb(0xFFFFFF, 1), argb(0xFFFFFF, 0.6), argb(0xFFFFFF, 0)], [0, 0.3, 0.5, 0.7, 1])
            c.setBlendMode(.destinationIn)
            linear(c, 0, 0, 256, 0, [argb(0xFFFFFF, 0), argb(0xFFFFFF, 1), argb(0xFFFFFF, 1), argb(0xFFFFFF, 0)], [0, 0.1, 0.9, 1])
            c.setBlendMode(.normal)
        }
    }()

    /** Soft full-cell glow for lines that would clear. */
    static let lineGlow: TileSprite = {
        cached("lineGlow", 64, 64, scale: fx) { c in
            c.addPath(rr(CGRect(x: 2, y: 2, width: 60, height: 60), 12))
            c.clip()
            radial(c, 32, 32, 44, [argb(0xFFFFFF, 0.85), argb(0xFFFFFF, 0.3)])
        }
    }()

    static let bulb: TileSprite = {
        cached("bulb", 24, 24, scale: fx) { c in
            c.addEllipse(in: CGRect(x: 0, y: 0, width: 24, height: 24))
            c.clip()
            radial(c, 12, 12, 12, [argb(0xFFFFFF), argb(0xFFE8A0, 0.9), argb(0xFFB020, 0)], [0, 0.35, 1])
        }
    }()

    /// The hint hand (Material `TouchApp` on Android, drawn with the vector's default black fill).
    static let hand: TileSprite = {
        cached("hand", 96, 96, scale: 2) { c in
            #if canImport(UIKit)
            let config = UIImage.SymbolConfiguration(pointSize: 80, weight: .regular)
            guard let symbol = UIImage(systemName: "hand.tap.fill", withConfiguration: config)?
                .withTintColor(.black, renderingMode: .alwaysOriginal) else { return }
            let box: CGFloat = 96 * 0.84
            let aspect = symbol.size.width / max(1, symbol.size.height)
            let w = aspect >= 1 ? box : box * aspect
            let h = aspect >= 1 ? box / aspect : box
            // The context is y-down like UIKit's, so UIKit can draw the symbol straight into it.
            UIGraphicsPushContext(c)
            symbol.draw(in: CGRect(x: (96 - w) / 2, y: (96 - h) / 2, width: w, height: h))
            UIGraphicsPopContext()
            #endif
        }
    }()

    /// Builds every sprite the scene draws for a cell size, so the first clear doesn't stutter.
    static func warmUp(_ cellPx: Int) {
        for t in 0..<tones.count { _ = block(t, cellPx) }
        for g in TileGem.allCases { _ = gem(g, cellPx) }
        _ = outline(cellPx)
        _ = board(cellPx, false)
        _ = board(cellPx, true)
        _ = glow; _ = sparkle; _ = ring; _ = bulb; _ = hand
        for t in 0..<tones.count {
            let tone = color(tones[t])
            _ = tint("shard", shard, tone.mix(.white, 0.15))
            _ = tint("lineGlow", lineGlow, tone.mix(.white, 0.35))
            _ = tint("beam", beam, tone)
        }
        _ = tint("glow", glow, color(0xFFB020))
    }

    // MARK: Labels

    private static var labels: [String: TileLabel] = [:]

    /// Scene text: Nunito Black at `size` px, a round-joined outline `size × 0.11` wide in `stroke`, filled with `fill`.
    static func label(_ text: String, _ size: CGFloat, _ fill: Int, _ stroke: Int) -> TileLabel {
        let key = "\(text)|\(Int(size * 10))|\(fill)|\(stroke)"
        lock.lock()
        if let l = labels[key] { lock.unlock(); return l }
        lock.unlock()
        let font = Nunito.uiFont(size, .black) as CTFont
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attr)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let height = ascent + descent
        let path = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let n = CTRunGetGlyphCount(run)
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = attrs[kCTFontAttributeName as String].map { $0 as! CTFont } ?? font
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var positions = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &positions)
            for k in 0..<n {
                guard let g = CTFontCreatePathForGlyph(runFont, glyphs[k], nil) else { continue }
                path.addPath(g, transform: CGAffineTransform(translationX: positions[k].x, y: positions[k].y))
            }
        }
        let strokeWidth = size * 0.11
        let pad = ceil(strokeWidth) + 2
        let w = max(1, Int(ceil(width + pad * 2)))
        let h = max(1, Int(ceil(height + pad * 2)))
        func layer(_ draw: (CGContext) -> Void) -> TileSprite {
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // Glyph paths are y-up: the baseline sits `descent` above the bottom of the layout box.
            ctx.translateBy(x: pad, y: pad + descent)
            ctx.addPath(path)
            draw(ctx)
            return TileSprite(ctx.makeImage()!)
        }
        let outline = layer { c in
            c.setLineWidth(strokeWidth)
            c.setLineJoin(.round)
            c.setLineCap(.round)
            c.setStrokeColor(argb(stroke))
            c.strokePath()
        }
        let inner = layer { c in
            c.setFillColor(argb(fill))
            c.fillPath()
        }
        let l = TileLabel(outline: outline, inner: inner, width: width, height: height, pad: pad)
        lock.lock()
        if labels.count > 160 { labels.removeAll() }
        labels[key] = l
        lock.unlock()
        return l
    }

    // MARK: Worlds

    struct World {
        let name: String
        let top: Int
        let bottom: Int
        let accent: Int
        let stars: Bool
    }

    static let worlds: [World] = [
        World(name: "Indigo Night", top: 0x2E2A8C, bottom: 0x6A4FE0, accent: 0x9F8CFF, stars: false),
        World(name: "Deep Ocean", top: 0x0B3C7A, bottom: 0x22A6D9, accent: 0x7FE3FF, stars: false),
        World(name: "Sunset Bay", top: 0x5E2172, bottom: 0xFF8A5B, accent: 0xFFC27A, stars: false),
        World(name: "Emerald Woods", top: 0x0F4A3A, bottom: 0x2FA872, accent: 0x9CF0B5, stars: false),
        World(name: "Candy Clouds", top: 0x8A3AB0, bottom: 0xFF8FC8, accent: 0xFFD3EC, stars: false),
        World(name: "Golden Dunes", top: 0x7A3E16, bottom: 0xF2B65E, accent: 0xFFE3A3, stars: false),
        World(name: "Arctic Lights", top: 0x173D6E, bottom: 0x7FD6F5, accent: 0xD9F7FF, stars: true),
        World(name: "Ember Peak", top: 0x2E0A18, bottom: 0xD6402B, accent: 0xFF9A5A, stars: false),
        World(name: "Neon Arcade", top: 0x120A36, bottom: 0x6A23D6, accent: 0xFF4FD8, stars: true),
        World(name: "Galaxy Core", top: 0x07051F, bottom: 0x3A1F86, accent: 0x7FE3FF, stars: true),
    ]

    static func world(_ i: Int) -> World { worlds[Kt.mod(i, worlds.count)] }

    /** The world's name as the level map shows it ("Galaxy Core III" on the third lap). */
    static func worldName(_ i: Int) -> String { lapName(world(i).name, max(i, 0) / worlds.count) }

    /** Full-screen backdrop: gradient, a soft perspective grid, stars and floating glass cubes. */
    static func background(_ index: Int, _ w: Int, _ h: Int, _ density: Float) -> TileSprite {
        cached("bg\(index)_\(w)x\(h)", w, h) { c in
            let world = world(index)
            let W = CGFloat(w)
            let H = CGFloat(h)
            let d = CGFloat(density)
            linear(c, 0, 0, 0, H, [argb(world.top), argb(world.bottom)])
            radial(c, W / 2, H * 0.45, H * 0.55, [argb(world.accent, 0.35), argb(world.accent, 0)])
            c.setLineWidth(d)
            c.setStrokeColor(argb(0xFFFFFF, 0.07))
            let vx = W / 2
            let vy = -H * 0.25
            for k in 0...14 {
                c.move(to: CGPoint(x: vx, y: vy))
                c.addLine(to: CGPoint(x: CGFloat(Float(k) / 14) * W * 1.8 - W * 0.4, y: H))
                c.strokePath()
            }
            for k in 0...14 {
                let y = H - H * CGFloat(Float(pow(Double(Float(k) / 14), 1.7)))
                c.move(to: CGPoint(x: 0, y: y))
                c.addLine(to: CGPoint(x: W, y: y))
                c.strokePath()
            }
            var rng = TileRNG(Int64(index * 977 + 13))
            if world.stars {
                for _ in 0..<90 {
                    let s = CGFloat(1 + rng.int(3)) * d
                    let x = CGFloat(Float(rng.unit())) * W
                    let y = H - CGFloat(Float(rng.unit())) * H
                    c.setFillColor(argb(0xFFFFFF, CGFloat(Float(0.3 + rng.unit() * 0.6))))
                    c.fillEllipse(in: CGRect(x: x, y: y, width: s, height: s))
                }
            }
            for _ in 0..<9 {
                let s = CGFloat(18 + rng.int(34)) * d
                let left = rng.int(2) == 0
                let x = left ? CGFloat(Float(rng.unit())) * W * 0.16 : W * (0.84 + CGFloat(Float(rng.unit())) * 0.16)
                let y = H - H * (0.06 + CGFloat(Float(rng.unit())) * 0.9)
                let alpha = 0.22 + CGFloat(Float(rng.unit())) * 0.2
                let rot = CGFloat(Float((rng.unit() - 0.5) * 0.8))
                let tone = mix(tones[rng.int(tones.count)], world.accent, 0.4)
                c.saveGState()
                c.setAlpha(alpha)
                c.beginTransparencyLayer(auxiliaryInfo: nil)
                c.translateBy(x: x, y: y)
                c.rotate(by: -rot)
                paintBlock(c, CGRect(x: -s / 2, y: -s / 2, width: s, height: s), tone)
                c.endTransparencyLayer()
                c.restoreGState()
            }
        }
    }
}
