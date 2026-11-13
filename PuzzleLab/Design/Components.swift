import SwiftUI

// MARK: - Shadows and glass

extension View {
    /// A soft coloured shadow under a rounded rect (or circle) the size of this view — the SwiftUI
    /// `.shadow(color:radius:y:)` the Android app re-creates with a shadow layer. Only the shadow is drawn,
    /// so it also works under glass. Apply it outside any clip.
    func labShadow(_ color: Color, _ blur: CGFloat, _ y: CGFloat = 0, _ corner: CGFloat = 0, circle: Bool = false) -> some View {
        let visible = color.alpha > 0
        return background {
            if visible { LabShadowView(color: color, blur: blur, y: y, corner: corner, circle: circle) }
        }
    }

    func labShadow(color: Color, blur: CGFloat, y: CGFloat = 0, corner: CGFloat = 0, circle: Bool = false) -> some View {
        labShadow(color, blur, y, corner, circle: circle)
    }
}

/// SwiftUI shadow/blur radius r blurs by ≈ r; Android (Skia) blurs by ≈ 0.577·r + 0.5 px for the same radius.
let shadowBlurScale: CGFloat = 0.58

private struct LabShadowView: View {
    let color: Color
    let blur: CGFloat
    let y: CGFloat
    let corner: CGFloat
    let circle: Bool

    var body: some View {
        let pad = blur * 2.5 + abs(y) + 2
        Canvas { ctx, size in
            let rect = CGRect(x: pad, y: pad, width: max(0, size.width - pad * 2), height: max(0, size.height - pad * 2))
            let r = circle ? min(rect.width, rect.height) / 2 : min(corner, min(rect.width, rect.height) / 2)
            var c = ctx
            c.addFilter(.shadow(color: color, radius: blur * shadowBlurScale, x: 0, y: y, blendMode: .normal, options: .shadowOnly))
            c.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(.black))
        }
        .padding(-pad)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension GraphicsContext {
    /// Kotlin `DrawScope.shadowRoundRect`: a soft shadow under a rounded rect, without the rect.
    func shadowRoundRect(_ rect: CGRect, _ radius: CGFloat, _ color: Color, _ blur: CGFloat, _ dy: CGFloat) {
        if blur <= 0 { return }
        var c = self
        c.addFilter(.shadow(color: color, radius: blur * shadowBlurScale, x: 0, y: dy, blendMode: .normal, options: .shadowOnly))
        c.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(.black))
    }
}

extension View {
    /// The Night Lab glass panel, bevelled like a game card: glass fill, a lit top edge, a darker lip along
    /// the bottom and a rim that fades from bright to dim. Apply after padding (Compose applies it before).
    func labGlass(_ radius: CGFloat = Lab.Radius.card) -> some View {
        modifier(LabGlassModifier(radius: radius))
    }
}

private struct LabGlassModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let lab = Lab.colors
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        content
            .background(
                ZStack {
                    lab.glass
                    LinearGradient(colors: [Color.white.opacity(min(1, lab.glassHighlightAlpha * 1.6)), .clear], startPoint: .top, endPoint: .center)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        LinearGradient(colors: [.clear, Color.black.opacity(lab.isDark ? 0.22 : 0.06)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 10)
                    }
                }
            )
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(lab.isDark ? 0.26 : 0.9), lab.glassStroke.copy(alpha: lab.glassStrokeAlpha * 0.6)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.2
                )
            )
    }
}

// MARK: - Presses

/// Press-down for cards and buttons: shrinks while held (snappy spring), taps on release.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(labSpring(0.28, 0.6), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Kotlin `Modifier.pressable(scale, enabled, sound, onClick)`. Wrap the finished card (after its
    /// background) so the whole card scales.
    func pressable(_ scale: CGFloat = 0.95, enabled: Bool = true, sound: Bool = false, onClick: @escaping () -> Void) -> some View {
        Button {
            if sound { UISound.tap() }
            onClick()
        } label: {
            self
        }
        .buttonStyle(PressableStyle(scale: scale))
        .disabled(!enabled)
    }
}

// MARK: - Buttons

/// Big gradient call to action (the iOS `.labPrimary`): a full-width game button.
struct LabPrimaryButton: View {
    let text: String
    var icon: ImageVector? = nil
    var trailingIcon: ImageVector? = nil
    var colors: [Color]? = nil
    var height: CGFloat = 58
    var enabled: Bool = true
    let onClick: () -> Void

    init(_ text: String, icon: ImageVector? = nil, trailingIcon: ImageVector? = nil, colors: [Color]? = nil, height: CGFloat = 58,
         enabled: Bool = true, onClick: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.trailingIcon = trailingIcon
        self.colors = colors
        self.height = height
        self.enabled = enabled
        self.onClick = onClick
    }

    var body: some View {
        GameButton(text, fill: true, icon: icon, trailingIcon: trailingIcon, colors: colors ?? GameColors.purple, height: height,
                   fontSize: height < 54 ? 17 : 19, enabled: enabled, onClick: onClick)
            .frame(maxWidth: .infinity)
    }
}

/// Slate pill button (secondary actions).
struct LabSecondaryButton: View {
    let text: String
    var fill: Bool = false
    var icon: ImageVector? = nil
    var height: CGFloat = 52
    let onClick: () -> Void

    init(_ text: String, fill: Bool = false, icon: ImageVector? = nil, height: CGFloat = 52, onClick: @escaping () -> Void) {
        self.text = text
        self.fill = fill
        self.icon = icon
        self.height = height
        self.onClick = onClick
    }

    var body: some View {
        GameButton(text, fill: fill, icon: icon, colors: GameColors.slate(), height: height, fontSize: 16, onClick: onClick)
    }
}

/// Round slate icon button (back, settings, close).
struct GlassIconButton: View {
    let icon: ImageVector
    var size: CGFloat = 44
    var tint: Color? = nil
    let onClick: () -> Void

    init(_ icon: ImageVector, size: CGFloat = 44, tint: Color? = nil, onClick: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.tint = tint
        self.onClick = onClick
    }

    var body: some View {
        GameIconButton(icon, colors: GameColors.slate(), size: size, iconSize: size * 0.46, iconTint: tint, onClick: onClick)
    }
}

/// Solid round icon button used in the play shell header (the iOS `CircleIconButton`).
struct CircleIconButton: View {
    let icon: ImageVector
    let onClick: () -> Void

    init(_ icon: ImageVector, onClick: @escaping () -> Void) {
        self.icon = icon
        self.onClick = onClick
    }

    var body: some View {
        GameIconButton(icon, colors: GameColors.slate(), size: 44, iconSize: 20, onClick: onClick)
    }
}

// MARK: - Badges and pills

/// A game's badge: its gradient, a radial shine and its own art.
struct GameBadgeFrame<Art: View>: View {
    let colors: [Color]
    let size: CGFloat
    var glow: Bool = true
    @ViewBuilder var art: () -> Art

    init(_ colors: [Color], _ size: CGFloat, glow: Bool = true, @ViewBuilder art: @escaping () -> Art) {
        self.colors = colors
        self.size = size
        self.glow = glow
        self.art = art
    }

    var body: some View {
        let corner = Lab.Radius.icon(size)
        let shape = RoundedRectangle(cornerRadius: corner, style: .circular)
        art()
            .frame(width: size * 0.8, height: size * 0.8)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(RadialGradient(colors: [Color.white.opacity(0.38), .clear], center: .topLeading, startRadius: 0, endRadius: size))
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: max(1, size / 64)))
            .labShadow(glow ? (colors.first ?? .white).copy(alpha: 0.45) : .clear, size * 0.18, size * 0.08, corner)
    }
}

/// Small pill with an icon and a number (streak, coins, stars).
struct StatPill: View {
    let icon: ImageVector
    let value: String
    var tint: Color? = nil

    init(_ icon: ImageVector, _ value: String, _ tint: Color? = nil) {
        self.icon = icon
        self.value = value
        self.tint = tint
    }

    var body: some View {
        let c = tint ?? Lab.colors.sun
        GameCounter(icon, value, [c.mix(.white, 0.25), c.mix(.black, 0.18)], height: 32)
    }
}

/// A difficulty chip under a level title.
struct TierChip: View {
    let title: String
    let icon: ImageVector
    let color: Color

    init(_ title: String, _ icon: ImageVector, _ color: Color) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 4) {
            Icon(icon, tint: color, size: 11)
            Text(title.uppercased()).font(rounded(11, .black)).tracking(1.1).foregroundStyle(color).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.18)))
    }
}

struct GlassDivider: View {
    var body: some View {
        Rectangle().fill(Lab.colors.glassStroke).frame(height: 1).padding(.leading, 58)
    }
}

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    init(_ title: String, action: String? = nil, onAction: (() -> Void)? = nil) {
        self.title = title
        self.action = action
        self.onAction = onAction
    }

    var body: some View {
        let lab = Lab.colors
        HStack(spacing: 0) {
            Text(title).font(LabText.headline).foregroundStyle(lab.ink).frame(maxWidth: .infinity, alignment: .leading)
            if let action, let onAction {
                Text(action).font(rounded(15, .bold)).foregroundStyle(lab.ink2)
                    .pressable(0.92) { UISound.tap(); onAction() }
            }
        }
    }
}

/// A coloured square icon with a title and an accessory, as in iOS Settings.
struct SettingsRow<Accessory: View>: View {
    let icon: ImageVector
    let color: Color
    let title: String
    var subtitle: String? = nil
    var titleColor: Color? = nil
    var onClick: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory

    init(_ icon: ImageVector, _ color: Color, _ title: String, subtitle: String? = nil, titleColor: Color? = nil,
         onClick: (() -> Void)? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.icon = icon
        self.color = color
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.onClick = onClick
        self.accessory = accessory
    }

    var body: some View {
        let lab = Lab.colors
        let row = HStack(spacing: 12) {
            GameIconBubble(icon, [color.mix(.white, 0.18), color.mix(.black, 0.18)], 34, circle: false, iconSize: 19)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(rounded(16, .bold)).foregroundStyle(titleColor ?? lab.ink).lineLimit(1).truncationMode(.tail)
                if let subtitle { Text(subtitle).font(rounded(12, .semibold)).foregroundStyle(lab.ink2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        if let onClick {
            row.pressable(0.98) { UISound.tap(); onClick() }
        } else {
            row
        }
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(_ icon: ImageVector, _ color: Color, _ title: String, subtitle: String? = nil, titleColor: Color? = nil, onClick: (() -> Void)? = nil) {
        self.init(icon, color, title, subtitle: subtitle, titleColor: titleColor, onClick: onClick) { EmptyView() }
    }
}

/// An iOS-style switch in the game style.
struct LabToggle: View {
    let checked: Bool
    let onChange: (Bool) -> Void

    init(_ checked: Bool, onChange: @escaping (Bool) -> Void) {
        self.checked = checked
        self.onChange = onChange
    }

    var body: some View { GameSwitch(checked, onChange: onChange) }
}

/// A segmented control on glass; the selected segment is a glossy key.
struct GlassSegmented<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    let selection: T
    let onSelect: (T) -> Void

    init(_ options: [T], _ title: @escaping (T) -> String, _ selection: T, onSelect: @escaping (T) -> Void) {
        self.options = options
        self.title = title
        self.selection = selection
        self.onSelect = onSelect
    }

    var body: some View {
        GameSegmented(options, title, selection, onSelect: onSelect).frame(maxWidth: .infinity)
    }
}

/// Circular progress (animates to its value).
struct ProgressRing<Fill: ShapeStyle>: View {
    let value: Double
    let lineWidth: CGFloat
    let track: Color
    let fill: Fill

    init(_ value: Double, _ lineWidth: CGFloat, _ track: Color, _ fill: Fill) {
        self.value = value
        self.lineWidth = lineWidth
        self.track = track
        self.fill = fill
    }

    var body: some View {
        let shown = value > 0 ? max(value, 0.03) : 0
        ZStack {
            Circle().inset(by: lineWidth / 2).stroke(track, lineWidth: lineWidth)
            Circle().inset(by: lineWidth / 2)
                .trim(from: 0, to: min(1, shown))
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(labSpring(0.6, 0.88), value: shown)
    }
}

/// A thin capsule progress bar.
struct CapsuleBar<Fill: ShapeStyle>: View {
    let fraction: Double
    let fill: Fill
    let track: Color
    var height: CGFloat = 8
    var minWidth: CGFloat = 8

    init(_ fraction: Double, _ fill: Fill, _ track: Color, height: CGFloat = 8, minWidth: CGFloat = 8) {
        self.fraction = fraction
        self.fill = fill
        self.track = track
        self.height = height
        self.minWidth = minWidth
    }

    var body: some View {
        let f = min(max(fraction, 0), 1)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(minWidth, geo.size.width * f))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .animation(labSpring(0.45, 0.75), value: f)
    }
}

// MARK: - Celebration

/// Celebration confetti; starts when it appears.
struct ConfettiView: View {
    var count: Int = 150
    var duration: Double = 4.2

    init(count: Int = 150, duration: Double = 4.2) {
        self.count = count
        self.duration = duration
    }

    private struct Particle {
        let x, vx, vy, sway, spin, w, h: Double
        let color: Int
        let delay: Double
        let circle: Bool
    }

    @State private var particles: [Particle] = []
    @State private var start = Date()
    @State private var done = false

    var body: some View {
        let lab = Lab.colors
        TimelineView(.animation(paused: done)) { timeline in
            let time = timeline.date.timeIntervalSince(start)
            Canvas { ctx, size in
                _ = time
                for p in particles {
                    let t = time - p.delay
                    if t <= 0 { continue }
                    let x = p.x * size.width + (p.vx * t + sin(t * 3 + p.spin) * p.sway)
                    let y = -30 + p.vy * t + 0.5 * 420 * t * t
                    if y > size.height + 40 { continue }
                    let fade = min(max((duration - t) / 0.8, 0), 1)
                    if fade <= 0 { continue }
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * t * 4))
                    let sy = abs(cos(p.spin * t * 3)) * 0.8 + 0.2
                    let w = p.w, h = p.h * sy
                    c.opacity = fade
                    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                    let color = lab.patch(p.color)
                    if p.circle {
                        c.fill(Path(ellipseIn: rect), with: .color(color))
                    } else {
                        c.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(nanoseconds: UInt64((duration + 1) * 1_000_000_000))
            done = true
            particles = []
        }
        .onAppear {
            start = Date()
            particles = (0..<count).map { _ in
                let w = Double.random(in: 0..<1) * 5 + 6
                return Particle(x: .random(in: 0..<1), vx: .random(in: 0..<1) * 80 - 40, vy: .random(in: 0..<1) * 280 - 120,
                                sway: .random(in: 0..<1) * 18 + 8, spin: .random(in: 0..<1) * 1.8 + 0.6, w: w,
                                h: w * (.random(in: 0..<1) * 0.35 + 0.45), color: Int.random(in: 0..<8),
                                delay: .random(in: 0..<1) * 0.9, circle: Bool.random() && Bool.random())
            }
        }
    }
}

/// Slowly turning light rays behind a celebration.
struct RotatingRays: View {
    let color: Color
    var rays: Int = 14
    var periodMs: Double = 24_000

    init(_ color: Color, rays: Int = 14, periodMs: Double = 24_000) {
        self.color = color
        self.rays = rays
        self.periodMs = periodMs
    }

    @State private var turn = false

    var body: some View {
        let reduce = Lab.reduceMotion
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = max(size.width, size.height) * 0.75
            for i in 0..<rays {
                let a0 = Double(i) * 2 * .pi / Double(rays)
                let a1 = a0 + .pi / Double(rays) * 0.55
                var path = Path()
                path.move(to: c)
                path.addLine(to: CGPoint(x: c.x + cos(a0) * r, y: c.y + sin(a0) * r))
                path.addLine(to: CGPoint(x: c.x + cos(a1) * r, y: c.y + sin(a1) * r))
                path.closeSubpath()
                ctx.fill(path, with: .radialGradient(Gradient(colors: [color.copy(alpha: 0.22), .clear]), center: c, startRadius: 0, endRadius: r))
            }
        }
        .rotationEffect(.degrees(turn ? 360 : 0))
        .onAppear {
            guard !reduce else { return }
            withAnimation(.linear(duration: periodMs / 1000).repeatForever(autoreverses: false)) { turn = true }
        }
        .allowsHitTesting(false)
    }
}

/// Plain centred empty state.
struct EmptyNote: View {
    let title: String
    let message: String

    init(_ title: String, _ message: String) {
        self.title = title
        self.message = message
    }

    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 6) {
            Text(title).font(LabText.headline).foregroundStyle(lab.ink)
            Text(message).font(LabText.body).foregroundStyle(lab.ink2).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

extension GraphicsContext {
    func drawGlassCircle(_ center: CGPoint, _ radius: CGFloat, _ fill: Color, _ stroke: Color) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        self.fill(Path(ellipseIn: rect), with: .color(fill))
        self.stroke(Path(ellipseIn: rect), with: .color(stroke), lineWidth: 1)
    }
}

struct HSpace: View {
    let w: CGFloat
    init(_ w: CGFloat) { self.w = w }
    var body: some View { Spacer().frame(width: w) }
}

struct VSpace: View {
    let h: CGFloat
    init(_ h: CGFloat) { self.h = h }
    var body: some View { Spacer().frame(height: h) }
}
