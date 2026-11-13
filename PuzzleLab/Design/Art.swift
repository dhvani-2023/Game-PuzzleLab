import SwiftUI

// MARK: - Backdrops

private struct Star {
    let x: Double
    let y: Double
    let r: Double
    let beat: Double
}

private let StarDust: [Star] = {
    var seed: Int64 = 0x2545_F491
    func next() -> Float {
        seed = (seed &* 1_103_515_245 &+ 12345) & 0x7FFF_FFFF
        return Float(seed) / 2_147_483_647
    }
    return (0..<34).map { _ in
        let x = next(), y = next(), r = 0.8 + next() * 1.3, beat = 1 + Float(Int(next() * 3))
        return Star(x: Double(x), y: Double(y), r: Double(r), beat: Double(beat))
    }
}()

/// The Night Lab backdrop: a vertical gradient with star dust and three slowly drifting colour glows.
struct LabBackground: View {
    var animated: Bool = true

    init(animated: Bool = true) { self.animated = animated }

    @State private var drift: CGFloat = 0

    var body: some View {
        let lab = Lab.colors
        let animate = animated && !Lab.reduceMotion
        let strength = lab.isDark ? 1.0 : 0.45
        lab.background2
            .overlay {
                if lab.isDark { StarDustLayer(animate: animate) }
            }
            .overlay {
                // Fixed-size glows overflow the screen; as an overlay they never change the layout.
                ZStack {
                    GlowBlob(color: LabGlows[0], alpha: 0.45 * strength, diameter: 420, blur: 110)
                        .offset(x: -150 + 40 * drift, y: -340 + 40 * drift)
                    GlowBlob(color: LabGlows[1], alpha: 0.28 * strength, diameter: 320, blur: 110)
                        .offset(x: 180 - 30 * drift, y: 30 + 40 * drift)
                    GlowBlob(color: LabGlows[2], alpha: 0.22 * strength, diameter: 340, blur: 120)
                        .offset(x: -130 + 40 * drift, y: 390 - 50 * drift)
                }
            }
            .clipped()
            .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard animate else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 9).repeatForever(autoreverses: true)) { drift = 1 }
        }
    }
}

/// One soft radial glow: full colour in the middle, 70% at `diameter/2` (×0.55 of the radius), fading out.
private struct GlowBlob: View {
    let color: Color
    let alpha: Double
    let diameter: CGFloat
    let blur: CGFloat

    var body: some View {
        let r = diameter / 2 + blur
        let mid = (diameter / 2 / (diameter / 2 + blur)) * 0.55
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: color.copy(alpha: alpha), location: 0),
                .init(color: color.copy(alpha: alpha * 0.7), location: mid),
                .init(color: color.copy(alpha: 0), location: 1),
            ], center: .center, startRadius: 0, endRadius: r))
            .frame(width: r * 2, height: r * 2)
    }
}

/// Star dust: tiny lights that twinkle on their own beats (6 s cycle), so every screen feels like a game world.
private struct StarDustLayer: View {
    let animate: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { timeline in
            let twinkle = animate ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 : 0.25
            Canvas { ctx, size in
                _ = twinkle
                for s in StarDust {
                    let a = 0.12 + 0.5 * (0.5 + 0.5 * sin((twinkle * s.beat + s.x * 7 + s.y * 3) * 2 * .pi))
                    let p = CGPoint(x: s.x * size.width, y: s.y * size.height)
                    let halo = s.r * 2.6
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - halo, y: p.y - halo, width: halo * 2, height: halo * 2)), with: .color(Color.white.opacity(a * 0.35)))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - s.r, y: p.y - s.r, width: s.r * 2, height: s.r * 2)), with: .color(Color.white.opacity(a)))
                }
            }
        }
    }
}

/// The plain soft backdrop used behind the Patches and Zip play screens (iOS `AmbientBackground`).
struct AmbientBackground: View {
    @State private var drift: CGFloat = 0

    var body: some View {
        let lab = Lab.colors
        let reduce = Lab.reduceMotion
        lab.background
            .overlay {
                ZStack {
                    AmbientBlob(color: lab.paletteBrand.copy(alpha: 0.16), diameter: 340, blur: 70).offset(x: -60 - 60 * drift, y: -240 - 60 * drift)
                    AmbientBlob(color: lab.patch(0).copy(alpha: 0.16), diameter: 280, blur: 70).offset(x: 100 + 50 * drift, y: 10 - 70 * drift)
                    AmbientBlob(color: lab.patch(3).copy(alpha: 0.14), diameter: 300, blur: 80).offset(x: -150 + 60 * drift, y: 280 + 50 * drift)
                }
            }
            .clipped()
            .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduce else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 9).repeatForever(autoreverses: true)) { drift = 1 }
        }
    }
}

private struct AmbientBlob: View {
    let color: Color
    let diameter: CGFloat
    let blur: CGFloat

    var body: some View {
        let r = diameter / 2 + blur
        Circle()
            .fill(RadialGradient(colors: [color, color.copy(alpha: color.alpha * 0.5), color.copy(alpha: 0)], center: .center, startRadius: 0, endRadius: r))
            .frame(width: r * 2, height: r * 2)
    }
}

// MARK: - Pinwheel

/// Coral, Honey, Mint, Sky and Lilac as (light, base, deep), matching the app icon.
private let PinwheelTones: [(Int, Int, Int)] = [
    (0xFFAE9F, 0xFF7A66, 0xD9533F),
    (0xFFE08A, 0xFFC93A, 0xE09E12),
    (0x8CEBC2, 0x46D39A, 0x22A873),
    (0x93B9FF, 0x4F8DFF, 0x2E66DB),
    (0xCDB3FF, 0xA67BFF, 0x7C52E0),
]

private struct PinPiece {
    let row: Int
    let col: Int
    let h: Int
    let w: Int
    let tone: Int
    let fx: CGFloat
    let fy: CGFloat
}

private let PinPieces = [
    PinPiece(row: 0, col: 0, h: 1, w: 2, tone: 0, fx: -1, fy: -1),
    PinPiece(row: 0, col: 2, h: 2, w: 1, tone: 1, fx: 1, fy: -1),
    PinPiece(row: 2, col: 1, h: 1, w: 2, tone: 2, fx: 1, fy: 1),
    PinPiece(row: 1, col: 0, h: 2, w: 1, tone: 3, fx: -1, fy: 1),
    PinPiece(row: 1, col: 1, h: 1, w: 1, tone: 4, fx: 0, fy: 0),
]

private let PinToneColors: [(Color, Color, Color)] = PinwheelTones.map { (hex($0.0), hex($0.1), hex($0.2)) }

/// The rounded-rect outline of every pinwheel tile in a `side`-pt square (for masks).
func pinwheelPath(_ side: CGFloat) -> Path {
    let unit = side / 3
    let gap = side * 0.05
    var path = Path()
    for p in PinPieces {
        path.addRoundedRect(in: pinRect(p, unit, gap), cornerSize: CGSize(width: unit * 0.3, height: unit * 0.3), style: .circular)
    }
    return path
}

private func pinRect(_ p: PinPiece, _ unit: CGFloat, _ gap: CGFloat) -> CGRect {
    let w = unit * CGFloat(p.w) - gap
    let h = unit * CGFloat(p.h) - gap
    let cx = unit * (CGFloat(p.col) + CGFloat(p.w) / 2)
    let cy = unit * (CGFloat(p.row) + CGFloat(p.h) / 2)
    return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
}

/// One jelly-glass tile: a lit-from-above gradient, a gloss band and a bright rim.
func jellyTile(_ ctx: GraphicsContext, _ rect: CGRect, _ unit: CGFloat, _ light: Color, _ base: Color, _ deep: Color, shadow: Bool = true) {
    let radius = unit * 0.3
    if shadow { ctx.shadowRoundRect(rect, radius, deep.copy(alpha: 0.45), unit * 0.12 * 2, unit * 0.08) }
    ctx.fill(Path(roundedRect: rect, cornerRadius: radius),
             with: .linearGradient(Gradient(colors: [light, base, deep]), startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
    let glossH = min(rect.height * 0.48, unit * 0.42)
    let gloss = CGRect(x: rect.minX + unit * 0.1, y: rect.minY + unit * 0.06, width: rect.width - unit * 0.2, height: glossH)
    ctx.fill(Path(roundedRect: gloss, cornerRadius: radius * 0.7),
             with: .linearGradient(Gradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0)]),
                                   startPoint: CGPoint(x: 0, y: gloss.minY), endPoint: CGPoint(x: 0, y: gloss.maxY)))
    let rim = max(0.5, unit * 0.04)
    ctx.stroke(Path(roundedRect: rect.insetBy(dx: rim / 2, dy: rim / 2), cornerRadius: max(0, radius - rim / 2)),
               with: .linearGradient(Gradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.1)]),
                                     startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)),
               lineWidth: rim)
}

/// The app mark drawn into a context: a solved 3×3 Patches board laid out as a pinwheel in glossy
/// jelly-glass tiles. `progress(i)` per piece runs 0 → 1 (springs may overshoot) as the pieces fly in.
func drawPinwheel(_ ctx: GraphicsContext, _ side: CGFloat, _ progress: (Int) -> Double = { _ in 1 }) {
    let unit = side / 3
    let gap = side * 0.05
    for (index, p) in PinPieces.enumerated() {
        let t = progress(index)
        if t <= 0.001 { continue }
        let isCenter = p.fx == 0 && p.fy == 0
        let alpha = min(max(t, 0), 1)
        let s = isCenter ? 0.05 + 0.95 * t : 0.55 + 0.45 * t
        let rot = (isCenter ? 90.0 : -28.0) * (1 - t)
        let rect = pinRect(p, unit, gap)
        var c = ctx
        c.translateBy(x: rect.midX + p.fx * side * 0.7 * (1 - t), y: rect.midY + p.fy * side * 0.7 * (1 - t))
        c.rotate(by: .degrees(rot))
        c.scaleBy(x: s, y: s)
        c.opacity = alpha
        let tone = PinToneColors[p.tone]
        jellyTile(c, CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height), unit, tone.0, tone.1, tone.2)
    }
}

/// The pinwheel logo; with `animateIn` the tiles fly in from the corners (90 ms apart).
struct PinwheelLogo: View {
    let size: CGFloat
    var animateIn: Bool = false
    var startDelayMs: Int = 0

    init(_ size: CGFloat, animateIn: Bool = false, startDelayMs: Int = 0) {
        self.size = size
        self.animateIn = animateIn
        self.startDelayMs = startDelayMs
    }

    var body: some View {
        if animateIn {
            AnimatedPinwheel(size: size, startDelayMs: startDelayMs)
        } else {
            StaticPinwheel(size: size)
        }
    }
}

private struct StaticPinwheel: View {
    let size: CGFloat

    var body: some View {
        let pad = size * 0.2
        Canvas { ctx, s in
            var c = ctx
            c.translateBy(x: pad, y: pad)
            drawPinwheel(c, size)
        }
        .frame(width: size + pad * 2, height: size + pad * 2)
        .padding(-pad)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Each tile is its own layer, flown in with a spring on GPU transforms (no per-frame redraw).
struct AnimatedPinwheel: View {
    let size: CGFloat
    var startDelayMs: Int = 0
    /// External per-piece progress (splash); nil = run the fly-in itself when it appears.
    var progress: [Double]? = nil

    @State private var shown: [Double] = [0, 0, 0, 0, 0]

    var body: some View {
        let values = progress ?? shown
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                PinTileLayer(index: i, side: size, t: values[i])
            }
        }
        .frame(width: size, height: size)
        .task {
            guard progress == nil else { return }
            if Lab.reduceMotion {
                shown = [1, 1, 1, 1, 1]
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(startDelayMs) * 1_000_000)
            for i in 0..<5 {
                withAnimation(labSpring(0.62, i == 4 ? 0.45 : 0.68).delay(Double(i) * 0.09)) { shown[i] = 1 }
            }
        }
    }
}

/// One pinwheel tile at progress `t`: scale, rotation and fly-in offset as `drawPinwheel` computes them.
struct PinTileLayer: View {
    let index: Int
    let side: CGFloat
    let t: Double

    var body: some View {
        let p = PinPieces[index]
        let unit = side / 3
        let rect = pinRect(p, unit, side * 0.05)
        let isCenter = p.fx == 0 && p.fy == 0
        let s = isCenter ? 0.05 + 0.95 * t : 0.55 + 0.45 * t
        let rot = (isCenter ? 90.0 : -28.0) * (1 - t)
        let anchor = UnitPoint(x: rect.midX / side, y: rect.midY / side)
        let pad = side * 0.2
        let tone = PinToneColors[p.tone]
        Canvas { ctx, _ in
            jellyTile(ctx, rect.offsetBy(dx: pad, dy: pad), unit, tone.0, tone.1, tone.2)
        }
        .frame(width: side + pad * 2, height: side + pad * 2)
        .padding(-pad)
        .frame(width: side, height: side)
        .scaleEffect(max(0.0001, s), anchor: anchor)
        .rotationEffect(.degrees(rot), anchor: anchor)
        .offset(x: p.fx * side * 0.7 * (1 - t), y: p.fy * side * 0.7 * (1 - t))
        .opacity(t <= 0.001 ? 0 : min(max(t, 0), 1))
    }
}

// MARK: - Avatars

/// The player's avatar: an emoji on a glossy disc in their colour.
struct ProfileAvatar: View {
    let avatar: String
    let color: Color
    let size: CGFloat

    init(_ avatar: String, _ color: Color, _ size: CGFloat) {
        self.avatar = avatar
        self.color = color
        self.size = size
    }

    var body: some View {
        let stroke = max(1.5, size * 0.05)
        let inset = size * 0.06
        ZStack {
            Circle().fill(LinearGradient(colors: [color.mix(.white, 0.25), color, color.mix(.black, 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(LinearGradient(stops: [.init(color: Color.white.opacity(0.45), location: 0), .init(color: .clear, location: (size / 2 - inset) / (size - inset * 2))],
                                     startPoint: .top, endPoint: .bottom))
                .padding(inset)
            Circle().inset(by: stroke / 2).stroke(Color.white.opacity(0.85), lineWidth: stroke)
            Text(avatar).font(.system(size: size * 0.5))
        }
        .frame(width: size, height: size)
        .labShadow(color.copy(alpha: 0.4), size * 0.12, size * 0.06, circle: true)
    }
}

// MARK: - Idle motion

/// Kotlin `rememberLoop(periodMs)`: a looping 0→1 phase for idle art (0.3 with Reduce Motion).
struct RememberLoop<Content: View>: View {
    let periodMs: Double
    @ViewBuilder let content: (Double) -> Content

    init(_ periodMs: Double, @ViewBuilder content: @escaping (Double) -> Content) {
        self.periodMs = periodMs
        self.content = content
    }

    var body: some View {
        let reduce = Lab.reduceMotion
        TimelineView(.animation(paused: reduce)) { timeline in
            let period = periodMs / 1000
            let phase = reduce ? 0.3 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            content(phase)
        }
    }
}

extension View {
    /// Kotlin `rememberFloat(amount, periodMs)`: a gentle up-and-down float for idle art; off with Reduce Motion.
    func floating(_ amount: CGFloat = 4, periodMs: Double = 3000, active: Bool = true) -> some View {
        modifier(FloatingModifier(amount: amount, periodMs: periodMs, active: active))
    }
}

private struct FloatingModifier: ViewModifier {
    let amount: CGFloat
    let periodMs: Double
    let active: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        let on = active && !Lab.reduceMotion
        content
            .offset(y: on ? (up ? amount : -amount) : 0)
            .onAppear { start(on) }
            .onChange(of: on) { _, v in start(v) }
    }

    private func start(_ on: Bool) {
        if on {
            up = false
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: periodMs / 1000).repeatForever(autoreverses: true)) { up = true }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { up = false }
        }
    }
}

struct SolidBox: View {
    let color: Color
    init(_ color: Color) { self.color = color }
    var body: some View { color }
}
