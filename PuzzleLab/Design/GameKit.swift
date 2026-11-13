import SwiftUI

// The 3D game kit (Kotlin design/GameKit.kt). Sizes follow Compose: a key's height includes its `depth`.
// Compose `Modifier.fillMaxWidth()` / `weight(1f)` on a key → `fill: true` (the face stretches);
// without it keys hug their content, as in Compose.

/// The game kit's key colours, top → bottom of each key's face.
enum GameColors {
    static let purple = [hex(0xA08BFF), hex(0x6A45F0)]
    static let green = [hex(0x6BEA9B), hex(0x1FA85A)]
    static let gold = [hex(0xFFD968), hex(0xF0930F)]
    static let red = [hex(0xFF7387), hex(0xD92C47)]
    static let blue = [hex(0x6BBBFF), hex(0x2F6BE0)]
    static let teal = [hex(0x5BE6CB), hex(0x15A088)]
    static let pink = [hex(0xFF8CC6), hex(0xE0458E)]
    static let white = [hex(0xFFFFFF), hex(0xE6E1F4)]
    private static let slateDark = [hex(0x625C8E), hex(0x3A3462)]
    private static let slateLight = [hex(0xFFFFFF), hex(0xE2DCF2)]

    /// The quiet key for secondary actions, in the current theme.
    static func slate() -> [Color] { Lab.colors.isDark ? slateDark : slateLight }

    /// Whether text on this face is dark (light faces such as `white` and light-theme slate).
    static func inkIsDark(_ face: [Color]) -> Bool { luminanceish(face.first ?? .white) > 0.8 }

    /// Text and icon colour that reads on a key face.
    static func ink(_ face: [Color]) -> Color { inkIsDark(face) ? hex(0x2B2350) : Color.white }

    private static func luminanceish(_ c: Color) -> Double {
        let v = c.rgba
        return 0.299 * v.r + 0.587 * v.g + 0.114 * v.b
    }
}

/// A 3D game key: a gradient face with a gloss cap and a bright rim, sitting on a darker base `depth`
/// below it that it presses down into, with a sound and a tap of haptics. Give it a height with
/// `.frame(height:)` (Compose `Modifier.height`), which includes the depth.
struct GameKey<Content: View>: View {
    var colors: [Color]
    var corner: CGFloat
    var depth: CGFloat = 5
    var enabled: Bool = true
    var sound: Bool = true
    var fill: Bool = false
    var onClick: (() -> Void)?
    @ViewBuilder var content: () -> Content

    init(colors: [Color], corner: CGFloat, depth: CGFloat = 5, enabled: Bool = true, sound: Bool = true, fill: Bool = false,
         onClick: (() -> Void)?, @ViewBuilder content: @escaping () -> Content) {
        self.colors = colors
        self.corner = corner
        self.depth = depth
        self.enabled = enabled
        self.sound = sound
        self.fill = fill
        self.onClick = onClick
        self.content = content
    }

    var body: some View {
        Group {
            if let onClick, enabled {
                Button {
                    if sound { UISound.tap() }
                    Haptics.tap()
                    onClick()
                } label: {
                    content()
                }
                .buttonStyle(GameKeyStyle(colors: colors, corner: corner, depth: depth, fill: fill))
            } else {
                GameKeyBody(label: content(), pressed: false, colors: colors, corner: corner, depth: depth, fill: fill)
            }
        }
        .opacity(enabled ? 1 : 0.5)
    }
}

struct GameKeyStyle: ButtonStyle {
    let colors: [Color]
    let corner: CGFloat
    let depth: CGFloat
    let fill: Bool

    func makeBody(configuration: Configuration) -> some View {
        GameKeyBody(label: configuration.label, pressed: configuration.isPressed, colors: colors, corner: corner, depth: depth, fill: fill)
    }
}

private struct GameKeyBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let colors: [Color]
    let corner: CGFloat
    let depth: CGFloat
    let fill: Bool

    var body: some View {
        let top = colors.first ?? .white
        let bottom = colors.last ?? .white
        let shape = RoundedRectangle(cornerRadius: corner, style: .circular)
        let p: CGFloat = pressed ? 1 : 0
        label
            .frame(maxWidth: fill ? .infinity : nil, maxHeight: .infinity)
            .background(KeyFace(top: top, bottom: bottom, corner: corner))
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .scaleEffect(1 - 0.02 * p)
            .offset(y: depth * p)
            .animation(labSpring(0.2, 0.62), value: pressed)
            .background(KeyBase(bottom: bottom, corner: corner).offset(y: depth))
            .padding(.bottom, depth)
            .contentShape(Rectangle())
    }
}

private struct KeyFace: View {
    let top: Color
    let bottom: Color
    let corner: CGFloat

    var body: some View {
        let lip = bottom.mix(.black, 0.25).copy(alpha: 0.55)
        LinearGradient(colors: [top.mix(.white, 0.18), top, bottom], startPoint: .top, endPoint: .bottom)
            .overlay(
                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    let gh = min(h * 0.44, 24)
                    let inset = min(w, h) * 0.12
                    let gloss = CGRect(x: inset, y: h * 0.06, width: w - inset * 2, height: gh)
                    ctx.fill(Path(roundedRect: gloss, cornerRadius: gh / 2),
                             with: .linearGradient(Gradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0)]),
                                                   startPoint: CGPoint(x: 0, y: h * 0.06), endPoint: CGPoint(x: 0, y: h * 0.06 + gh)))
                    // A thin darker line along the bottom of the face, so it reads as a raised cap.
                    ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: min(corner, h / 2)),
                             with: .linearGradient(Gradient(colors: [Color.clear, lip]),
                                                   startPoint: CGPoint(x: 0, y: h * 0.72), endPoint: CGPoint(x: 0, y: h)))
                }
            )
    }
}

private struct KeyBase: View {
    let bottom: Color
    let corner: CGFloat

    var body: some View {
        GeometryReader { geo in
            let r = min(corner, geo.size.height / 2, geo.size.width / 2)
            RoundedRectangle(cornerRadius: r, style: .circular)
                .fill(LinearGradient(colors: [bottom.mix(.black, 0.3), bottom.mix(.black, 0.5)], startPoint: .top, endPoint: .bottom))
                .labShadow(bottom.mix(.black, 0.55).copy(alpha: 0.5), 12, 4, r)
        }
    }
}

/// A full-width (or sized) 3D game button with a label and optional icons.
struct GameButton: View {
    let text: String
    var fill: Bool = false
    var icon: ImageVector? = nil
    var trailingIcon: ImageVector? = nil
    var colors: [Color] = GameColors.purple
    var height: CGFloat = 58
    var fontSize: CGFloat = 19
    var enabled: Bool = true
    let onClick: () -> Void

    init(_ text: String, fill: Bool = false, icon: ImageVector? = nil, trailingIcon: ImageVector? = nil, colors: [Color] = GameColors.purple,
         height: CGFloat = 58, fontSize: CGFloat = 19, enabled: Bool = true, onClick: @escaping () -> Void) {
        self.text = text
        self.fill = fill
        self.icon = icon
        self.trailingIcon = trailingIcon
        self.colors = colors
        self.height = height
        self.fontSize = fontSize
        self.enabled = enabled
        self.onClick = onClick
    }

    var body: some View {
        let darkInk = GameColors.inkIsDark(colors)
        let ink = GameColors.ink(colors)
        let shadow = darkInk ? Color.white.opacity(0.6) : (colors.last ?? .black).mix(.black, 0.45).copy(alpha: 0.7)
        GameKey(colors: colors, corner: height / 2, depth: height >= 50 ? 5 : 4, enabled: enabled, fill: fill, onClick: onClick) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, tint: ink, size: fontSize + 3) }
                Text(text).font(gameTextStyle(fontSize, shadow)).foregroundStyle(ink).lineLimit(1)
                if let trailingIcon { Icon(trailingIcon, tint: ink, size: fontSize + 1) }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: height)
    }
}

/// A round 3D key with an icon (back, settings, help, tools).
struct GameIconButton: View {
    let icon: ImageVector
    var colors: [Color]? = nil
    var size: CGFloat = 46
    var iconSize: CGFloat = 21
    var iconTint: Color? = nil
    var enabled: Bool = true
    let onClick: () -> Void

    init(_ icon: ImageVector, colors: [Color]? = nil, size: CGFloat = 46, iconSize: CGFloat = 21, iconTint: Color? = nil,
         enabled: Bool = true, onClick: @escaping () -> Void) {
        self.icon = icon
        self.colors = colors
        self.size = size
        self.iconSize = iconSize
        self.iconTint = iconTint
        self.enabled = enabled
        self.onClick = onClick
    }

    var body: some View {
        let face = colors ?? GameColors.purple
        GameKey(colors: face, corner: size / 2, depth: 4, enabled: enabled, fill: true, onClick: onClick) {
            Icon(icon, tint: iconTint ?? GameColors.ink(face), size: iconSize)
        }
        .frame(width: size, height: size + 4)
    }
}

/// The back key used on every pushed screen.
struct GameBackButton: View {
    var colors: [Color]? = nil
    let onClick: () -> Void

    init(colors: [Color]? = nil, onClick: @escaping () -> Void) {
        self.colors = colors
        self.onClick = onClick
    }

    var body: some View {
        GameIconButton(Icons.AutoMirrored.Rounded.ArrowBack, colors: colors, iconSize: 22, onClick: onClick)
    }
}

/// A rounded-square tool key with an icon over a label (Undo, Clear, Hint…). Fills its width.
struct GameToolKey: View {
    let title: String
    let icon: ImageVector
    let colors: [Color]
    var enabled: Bool = true
    var badge: String? = nil
    var badgeColors: [Color] = GameColors.red
    let onClick: () -> Void

    init(_ title: String, _ icon: ImageVector, _ colors: [Color], enabled: Bool = true, badge: String? = nil,
         badgeColors: [Color] = GameColors.red, onClick: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.colors = colors
        self.enabled = enabled
        self.badge = badge
        self.badgeColors = badgeColors
        self.onClick = onClick
    }

    var body: some View {
        let darkInk = GameColors.inkIsDark(colors)
        let ink = GameColors.ink(colors)
        ZStack(alignment: .topTrailing) {
            GameKey(colors: colors, corner: 20, depth: 5, enabled: enabled, fill: true, onClick: onClick) {
                VStack(spacing: 3) {
                    Icon(icon, tint: ink, size: 24)
                    Text(title)
                        .font(gameTextStyle(13, darkInk ? Color.clear : (colors.last ?? .black).mix(.black, 0.45).copy(alpha: 0.6)))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                }
            }
            .frame(height: 72)
            if let badge {
                GameBadge(badge, colors: badgeColors).offset(x: 4, y: -6)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A small glossy count bubble that sits on a key's corner.
struct GameBadge: View {
    let text: String
    var colors: [Color] = GameColors.red
    var icon: ImageVector? = nil

    init(_ text: String, colors: [Color] = GameColors.red, icon: ImageVector? = nil) {
        self.text = text
        self.colors = colors
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 2) {
            if let icon { Icon(icon, tint: .white, size: 11) }
            Text(text).font(rounded(11, .black)).foregroundStyle(Color.white).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(LinearGradient(colors: [colors.first ?? .red, colors.last ?? .red], startPoint: .top, endPoint: .bottom))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1.5))
        .labShadow((colors.last ?? .red).copy(alpha: 0.5), 4, 2, 11)
    }
}

/// A glossy 3D bubble behind an icon (counters, settings rows, ribbons).
struct GameIconBubble: View {
    let icon: ImageVector
    let colors: [Color]
    let size: CGFloat
    var circle: Bool = true
    var iconSize: CGFloat? = nil

    init(_ icon: ImageVector, _ colors: [Color], _ size: CGFloat, circle: Bool = true, iconSize: CGFloat? = nil) {
        self.icon = icon
        self.colors = colors
        self.size = size
        self.circle = circle
        self.iconSize = iconSize
    }

    var body: some View {
        let corner = circle ? size / 2 : size * 0.28
        let shape = RoundedRectangle(cornerRadius: corner, style: .circular)
        let first = colors.first ?? .white, last = colors.last ?? .white
        Icon(icon, tint: .white, size: iconSize ?? size * 0.56)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [first.mix(.white, 0.15), first, last], startPoint: .top, endPoint: .bottom)
                    .overlay(
                        Canvas { ctx, s in
                            let w = s.width
                            ctx.fill(Path(roundedRect: CGRect(x: w * 0.16, y: w * 0.06, width: w * 0.68, height: w * 0.4), cornerRadius: w * 0.2),
                                     with: .linearGradient(Gradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)]),
                                                           startPoint: CGPoint(x: 0, y: w * 0.06), endPoint: CGPoint(x: 0, y: w * 0.5)))
                        }
                    )
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
            .labShadow(last.mix(.black, 0.3).copy(alpha: 0.45), 4, 2, corner)
    }
}

/// A game counter (coins, streak, timer): an inset capsule with a glossy icon bubble poking out on the
/// left, and an optional green "+" key on the right.
struct GameCounter: View {
    let icon: ImageVector
    let value: String
    let colors: [Color]
    var height: CGFloat = 36
    var onPlus: (() -> Void)? = nil
    var onClick: (() -> Void)? = nil

    init(_ icon: ImageVector, _ value: String, _ colors: [Color], height: CGFloat = 36, onPlus: (() -> Void)? = nil, onClick: (() -> Void)? = nil) {
        self.icon = icon
        self.value = value
        self.colors = colors
        self.height = height
        self.onPlus = onPlus
        self.onClick = onClick
    }

    var body: some View {
        let lab = Lab.colors
        let track = lab.isDark ? Color.black.opacity(0.32) : hex(0x2B2350, 0.1)
        let content = ZStack(alignment: .leading) {
            HStack(spacing: 6) {
                Text(value)
                    .font(gameTextStyle(15, Color.black.opacity(lab.isDark ? 0.45 : 0.12)))
                    .foregroundStyle(lab.ink)
                    .lineLimit(1)
                    .fixedSize()
                if let onPlus {
                    GameKey(colors: GameColors.green, corner: 12, depth: 3, fill: true, onClick: onPlus) {
                        Icon(Icons.Rounded.Add, tint: .white, size: 16)
                    }
                    .frame(width: 24, height: 27)
                }
            }
            .padding(.leading, height * 0.62)
            .padding(.trailing, onPlus != nil ? 4 : 12)
            .frame(height: height - 4)
            .background(
                track.overlay(
                    LinearGradient(stops: [.init(color: Color.black.opacity(0.25), location: 0), .init(color: .clear, location: 0.35)],
                                   startPoint: .top, endPoint: .bottom)
                )
            )
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.black.opacity(0.2), Color.white.opacity(0.18)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .padding(.leading, height * 0.5)
            .padding(.top, 2)
            GameIconBubble(icon, colors, height)
        }
        .frame(height: height + 2)
        if let onClick {
            content.pressable(0.95, sound: true, onClick: onClick)
        } else {
            content
        }
    }
}

/// A chunky game switch: an inset track that turns green, with a glossy 3D knob.
struct GameSwitch: View {
    let checked: Bool
    let onChange: (Bool) -> Void

    init(_ checked: Bool, onChange: @escaping (Bool) -> Void) {
        self.checked = checked
        self.onChange = onChange
    }

    var body: some View {
        let lab = Lab.colors
        let off = lab.isDark ? Color.black.opacity(0.35) : hex(0x2B2350, 0.14)
        let t: Double = checked ? 1 : 0
        ZStack(alignment: .leading) {
            Capsule().fill(off)
            Capsule().fill(LinearGradient(colors: [GameColors.green[0], GameColors.green[1]], startPoint: .top, endPoint: .bottom)).opacity(t)
            Capsule().fill(LinearGradient(stops: [.init(color: Color.black.opacity(0.28), location: 0), .init(color: .clear, location: 0.4)],
                                          startPoint: .top, endPoint: .bottom))
            Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            SwitchKnob()
                .padding(3)
                .offset(x: t * 24)
        }
        .frame(width: 56, height: 32)
        .clipShape(Capsule())
        .animation(labSpring(0.3, 0.66), value: checked)
        .contentShape(Capsule())
        .onTapGesture {
            UISound.toggle()
            Haptics.toggle()
            onChange(!checked)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(checked ? "On" : "Off")
    }
}

private struct SwitchKnob: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color.white, hex(0xE4E0F2)], startPoint: .top, endPoint: .bottom))
            .overlay(
                Canvas { ctx, s in
                    let w = s.width
                    ctx.fill(Path(ellipseIn: CGRect(x: w * 0.2, y: w * 0.1, width: w * 0.6, height: w * 0.36)),
                             with: .linearGradient(Gradient(colors: [Color.white, Color.white.opacity(0)]),
                                                   startPoint: CGPoint(x: 0, y: w * 0.1), endPoint: CGPoint(x: 0, y: w * 0.5)))
                }
            )
            .overlay(Circle().strokeBorder(hex(0xC9C2E6), lineWidth: 1))
            .frame(width: 26, height: 26)
            .labShadow(Color.black.opacity(0.35), 4, 2, circle: true)
    }
}

/// A row of choices on an inset track; the chosen one is a glossy key.
struct GameSegmented<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    let selection: T
    var colors: [Color] = GameColors.purple
    let onSelect: (T) -> Void

    init(_ options: [T], _ title: @escaping (T) -> String, _ selection: T, colors: [Color] = GameColors.purple, onSelect: @escaping (T) -> Void) {
        self.options = options
        self.title = title
        self.selection = selection
        self.colors = colors
        self.onSelect = onSelect
    }

    var body: some View {
        let lab = Lab.colors
        let track = lab.isDark ? Color.black.opacity(0.3) : hex(0x2B2350, 0.08)
        let first = colors.first ?? .white, last = colors.last ?? .white
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                ZStack {
                    if selected {
                        Capsule()
                            .fill(LinearGradient(colors: [first.mix(.white, 0.15), first, last], startPoint: .top, endPoint: .bottom))
                            .overlay(
                                Canvas { ctx, s in
                                    ctx.fill(Path(roundedRect: CGRect(x: s.width * 0.08, y: s.height * 0.08, width: s.width * 0.84, height: s.height * 0.4), cornerRadius: s.height * 0.2),
                                             with: .linearGradient(Gradient(colors: [Color.white.opacity(0.45), .clear]),
                                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height * 0.5)))
                                }
                                .clipShape(Capsule())
                            )
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
                            .labShadow(last.copy(alpha: 0.5), 6, 2, 18)
                    }
                    if selected {
                        Text(title(option)).font(gameTextStyle(14, last.mix(.black, 0.4).copy(alpha: 0.6))).foregroundStyle(Color.white).lineLimit(1)
                    } else {
                        Text(title(option)).font(rounded(14, .heavy)).foregroundStyle(lab.ink2).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    UISound.tap()
                    Haptics.tap()
                    onSelect(option)
                }
            }
        }
        .padding(4)
        .frame(height: 44)
        .background(
            track.overlay(
                LinearGradient(stops: [.init(color: Color.black.opacity(0.22), location: 0), .init(color: .clear, location: 0.4)], startPoint: .top, endPoint: .bottom)
            )
        )
        .clipShape(Capsule())
    }
}

/// A small glossy ribbon label for section headings.
struct GameRibbon: View {
    let text: String
    var colors: [Color] = GameColors.purple

    init(_ text: String, _ colors: [Color] = GameColors.purple) {
        self.text = text
        self.colors = colors
    }

    var body: some View {
        let first = colors.first ?? .white, last = colors.last ?? .white
        let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
        Text(text.uppercased())
            .font(gameTextStyle(11.5, last.mix(.black, 0.4).copy(alpha: 0.6)))
            .tracking(1.3)
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(
                LinearGradient(colors: [first, last], startPoint: .top, endPoint: .bottom)
                    .overlay(
                        Canvas { ctx, s in
                            ctx.fill(Path(roundedRect: CGRect(x: s.width * 0.04, y: 2, width: s.width * 0.92, height: s.height * 0.45), cornerRadius: s.height * 0.25),
                                     with: .linearGradient(Gradient(colors: [Color.white.opacity(0.4), .clear]),
                                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height * 0.55)))
                        }
                    )
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
            .labShadow(last.copy(alpha: 0.4), 6, 2, 12)
    }
}

extension View {
    /// A game popup frame: a raised surface with a glowing gradient rim and a lit top edge, used by every
    /// card and dialog. Apply after the content's padding (Compose applies it before `.padding`).
    func gamePopup(_ radius: CGFloat = 32, _ accent: [Color]? = nil) -> some View {
        modifier(GamePopupModifier(radius: radius, accent: accent))
    }
}

private struct GamePopupModifier: ViewModifier {
    let radius: CGFloat
    let accent: [Color]?

    func body(content: Content) -> some View {
        let lab = Lab.colors
        let rim = accent ?? [lab.brand2, lab.brand]
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        content
            .background(
                LinearGradient(colors: [lab.surface.mix(.white, lab.isDark ? 0.05 : 0), lab.surface, lab.surface.mix(.black, lab.isDark ? 0.18 : 0.04)],
                               startPoint: .top, endPoint: .bottom)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [Color.white.opacity(lab.isDark ? 0.08 : 0.5), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 60)
                    }
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [(rim.first ?? .white).copy(alpha: 0.95), (rim.last ?? .white).copy(alpha: 0.35)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 2))
            .labShadow(Color.black.opacity(0.4), 30, 14, radius)
    }
}
