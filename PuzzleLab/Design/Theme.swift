import SwiftUI
import UIKit
import Observation
import GameKit

// MARK: - Colour helpers

/// Kotlin `hex(0xRRGGBB, alpha)`.
func hex<T: BinaryInteger>(_ rgb: T, _ alpha: Double = 1) -> Color {
    let v = UInt32(truncatingIfNeeded: Int64(rgb))
    return Color(.sRGB,
                 red: Double((v >> 16) & 0xFF) / 255,
                 green: Double((v >> 8) & 0xFF) / 255,
                 blue: Double(v & 0xFF) / 255,
                 opacity: alpha)
}

func hex<T: BinaryInteger>(_ rgb: T, alpha: Double) -> Color { hex(rgb, alpha) }

extension Color {
    /// sRGB components 0…1 (r, g, b, a).
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// Compose `Color.alpha`.
    var alpha: Double { rgba.a }

    /// Compose `color.copy(alpha = x)`: the same colour with alpha set to `x` (not multiplied).
    func copy(alpha: Double) -> Color {
        let c = rgba
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: min(max(alpha, 0), 1))
    }


    /// Kotlin `Color.mix(other, by)`: Compose `lerp`, which interpolates in Oklab (alpha linearly).
    func mix(_ other: Color, _ by: Double) -> Color {
        let t = min(max(by, 0), 1)
        let a = rgba, b = other.rgba
        let la = Oklab.from(a.r, a.g, a.b), lb = Oklab.from(b.r, b.g, b.b)
        let rgb = Oklab.toSRGB(la.0 + (lb.0 - la.0) * t, la.1 + (lb.1 - la.1) * t, la.2 + (lb.2 - la.2) * t)
        return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: a.a + (b.a - a.a) * t)
    }

    func mix(_ other: Color, by: Double) -> Color { mix(other, by) }

    /// Kotlin `Color.deepen(by)` from GameModule.kt.
    func deepen(_ by: Double) -> Color { mix(.black, by) }
}

/// Björn Ottosson's Oklab (what Compose's `lerp(Color, Color, t)` uses).
enum Oklab {
    private static func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func enc(_ c: Double) -> Double {
        let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        return min(max(v, 0), 1)
    }

    static func from(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let lr = lin(r), lg = lin(g), lb = lin(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func toSRGB(_ L: Double, _ A: Double, _ B: Double) -> (Double, Double, Double) {
        let l_ = L + 0.3963377774 * A + 0.2158037573 * B
        let m_ = L - 0.1055613458 * A - 0.0638541728 * B
        let s_ = L - 0.0894841775 * A - 1.2914855480 * B
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return (enc(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                enc(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                enc(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }
}

// MARK: - Palette

/// Night Lab colour tokens. Every one has a light and a dark value, like the iOS asset catalog.
struct LabPalette {
    let isDark: Bool
    let bgTop: Color
    let bgBottom: Color
    let glass: Color
    let glassStroke: Color
    let glassHighlight: Color
    let ink: Color
    let ink2: Color
    let inkSecondary: Color
    let brand: Color
    let brand2: Color
    let paletteBrand: Color
    let paletteBrandEnd: Color
    let background: Color
    let surface: Color
    let surfaceAlt: Color
    let gridLine: Color
    let sun: Color
    let ok: Color
    let warn: Color
    let danger: Color
    let patches: [Color]
    /// Alphas of the translucent tokens (Compose reads `glass.alpha` etc.).
    let glassAlpha: Double
    let glassStrokeAlpha: Double
    let glassHighlightAlpha: Double

    func patch(_ index: Int) -> Color { patches[((index % patches.count) + patches.count) % patches.count] }
    var brandGradient: LinearGradient { LinearGradient(colors: [brand, brand2], startPoint: .leading, endPoint: .trailing) }
    var background2: LinearGradient { LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom) }
}

let DarkLab = LabPalette(
    isDark: true,
    bgTop: hex(0x231C52), bgBottom: hex(0x14112E),
    glass: Color.white.opacity(0.08), glassStroke: Color.white.opacity(0.14), glassHighlight: Color.white.opacity(0.06),
    ink: hex(0xF4F3FA), ink2: hex(0xC9C4EE), inkSecondary: hex(0xA4A2B8),
    brand: hex(0x6E5BFF), brand2: hex(0xB45CFF),
    paletteBrand: hex(0x8A7BFF), paletteBrandEnd: hex(0xC084FC),
    background: hex(0x0E0F1A), surface: hex(0x1A1B2B), surfaceAlt: hex(0x24253A), gridLine: hex(0x2E2F45),
    sun: hex(0xFFC266), ok: hex(0x34D399), warn: hex(0xFF8A3D), danger: hex(0xFB7185),
    patches: [0xFF7A66, 0xF5A14A, 0xE8C33A, 0x4FC48A, 0x3FB5C4, 0x5B92F0, 0x9277F5, 0xE772B1].map { hex($0) },
    glassAlpha: 0.08, glassStrokeAlpha: 0.14, glassHighlightAlpha: 0.06
)

let LightLab = LabPalette(
    isDark: false,
    bgTop: hex(0xF4F1FF), bgBottom: hex(0xFBF9F4),
    glass: Color.white.opacity(0.72), glassStroke: hex(0x1C1B29, 0.08), glassHighlight: Color.white.opacity(0.9),
    ink: hex(0x1C1B29), ink2: hex(0x5E5A78), inkSecondary: hex(0x6D6A7C),
    brand: hex(0x5B47F5), brand2: hex(0x9B5CF6),
    paletteBrand: hex(0x5B47F5), paletteBrandEnd: hex(0x9B5CF6),
    background: hex(0xF7F5F0), surface: hex(0xFFFFFF), surfaceAlt: hex(0xEFECE5), gridLine: hex(0xE2DED4),
    sun: hex(0xFFB547), ok: hex(0x1FB985), warn: hex(0xE8711F), danger: hex(0xEF4A6A),
    patches: [0xFF8F7A, 0xFFB561, 0xFFD84D, 0x6FD6A0, 0x5BC9D6, 0x74A9FF, 0xA68BFF, 0xF68BC4].map { hex($0) },
    glassAlpha: 0.72, glassStrokeAlpha: 0.08, glassHighlightAlpha: 0.9
)

/// The three ambient glows behind every shell screen.
let LabGlows = [hex(0x6E5BFF), hex(0xFF5C93), hex(0x2FB9A0)]

// MARK: - Theme state

/// Which palette and motion level apply now (Compose `LabTheme` + `LocalLab` / `LocalReduceMotion`).
/// Reading it inside a view body subscribes the view to theme changes.
@Observable
final class LabTheme {
    static let shared = LabTheme()

    /// The device's own appearance (for Theme = System).
    var systemDark: Bool
    /// The device's Reduce Motion accessibility setting.
    var systemReduceMotion: Bool

    private init() {
        systemDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        systemReduceMotion = UIAccessibility.isReduceMotionEnabled
    }

    var settings: AppSettings { AppState.shared.settings }

    var dark: Bool {
        switch settings.theme {
        case .System: return systemDark
        case .Light: return false
        case .Dark: return true
        }
    }

    var reduceMotion: Bool { settings.reducesMotion(systemReduceMotion) }

    /// Re-reads the device settings (called when the app becomes active).
    @MainActor func refreshSystem() {
        let d = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        if d != systemDark { systemDark = d }
        let r = UIAccessibility.isReduceMotionEnabled
        if r != systemReduceMotion { systemReduceMotion = r }
        GameKit.Motion.appReduceMotion = reduceMotion
    }
}

enum Lab {
    static var colors: LabPalette { LabTheme.shared.dark ? DarkLab : LightLab }
    static var reduceMotion: Bool { LabTheme.shared.reduceMotion }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static func gutter(_ width: CGFloat) -> CGFloat { width < 375 ? 16 : 20 }
    }

    enum Radius {
        static let small: CGFloat = 14
        static let card: CGFloat = 22
        static let bigCard: CGFloat = 26
        static let hero: CGFloat = 32
        static func icon(_ side: CGFloat) -> CGFloat { side * 0.225 }
    }
}

// MARK: - Type

/// Kotlin `FontWeight.X` names → SwiftUI weights (ExtraBold is `.heavy`).
enum FontWeight {
    static let Normal = Font.Weight.regular
    static let Medium = Font.Weight.medium
    static let SemiBold = Font.Weight.semibold
    static let Bold = Font.Weight.bold
    static let ExtraBold = Font.Weight.heavy
    static let Black = Font.Weight.black
}

extension Font.Weight {
    static let extraBold = Font.Weight.heavy
    static let semiBold = Font.Weight.semibold
    static let normal = Font.Weight.regular
}

/// Nunito, a rounded face standing in for SF Rounded: one variable font, every weight.
enum Nunito {
    static let postScriptName = "Nunito-Regular"
    private static var cache: [Int: Font] = [:]
    private static var uiCache: [Int: UIFont] = [:]
    private static let lock = NSLock()

    static func axis(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight, .thin: return 200
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }

    private static func key(_ size: CGFloat, _ w: CGFloat) -> Int { Int((size * 100).rounded()) * 10_000 + Int(w) }

    /// Nunito at an exact point size (not scaled by Dynamic Type) and weight.
    static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let w = axis(weight)
        let k = key(size, w)
        lock.lock(); defer { lock.unlock() }
        if let f = cache[k] { return f }
        let f = Font(uiFontLocked(size, w) as CTFont)
        cache[k] = f
        return f
    }

    static func uiFont(_ size: CGFloat, _ weight: Font.Weight) -> UIFont {
        lock.lock(); defer { lock.unlock() }
        return uiFontLocked(size, axis(weight))
    }

    private static func uiFontLocked(_ size: CGFloat, _ w: CGFloat) -> UIFont {
        let k = key(size, w)
        if let f = uiCache[k] { return f }
        let f = FontRegistry.variable(postScriptName, size: size, weight: w)
        uiCache[k] = f
        return f
    }
}

/// `Font.rounded(size, weight)` from the iOS code, in Nunito. Nunito runs a touch small, so sizes are
/// nudged up 4% (as on Android).
func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    Nunito.font(size * 1.04, weight)
}

/// `rounded` with letter spacing (Compose `tracking` in sp): use with `.font(…)` on any view.
func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular, tracking: CGFloat) -> LabStyle {
    LabStyle(font: rounded(size, weight), tracking: tracking)
}

/// A Compose `TextStyle` the SwiftUI way: font, letter spacing and an optional hard drop shadow.
struct LabStyle {
    var font: Font
    var tracking: CGFloat = 0
    var shadow: Color? = nil
    var shadowY: CGFloat = 0
}

extension View {
    /// Applies a `LabStyle` (font + tracking + drop shadow), e.g. `.font(LabText.title)`.
    func font(_ style: LabStyle) -> some View {
        modifier(LabStyleModifier(style: style))
    }
}

private struct LabStyleModifier: ViewModifier {
    let style: LabStyle

    func body(content: Content) -> some View {
        let base = content.font(style.font).tracking(style.tracking)
        if let s = style.shadow {
            base.shadow(color: s, radius: 0, x: 0, y: style.shadowY)
        } else {
            base
        }
    }
}

/// Chunky game text: heavy rounded type with a hard drop shadow under it.
func gameTextStyle(_ size: CGFloat, _ shadowColor: Color = Color.black.opacity(0.32), _ weight: Font.Weight = .black) -> LabStyle {
    LabStyle(font: rounded(size, weight), shadow: shadowColor, shadowY: 2.2)
}

func gameTextStyle(_ size: CGFloat, shadowColor: Color, weight: Font.Weight = .black) -> LabStyle {
    gameTextStyle(size, shadowColor, weight)
}

func gameTextStyle(_ size: CGFloat, weight: Font.Weight) -> LabStyle {
    gameTextStyle(size, Color.black.opacity(0.32), weight)
}

enum LabText {
    private static let drop = Color.black.opacity(0.32)
    static let display = LabStyle(font: rounded(38, .black), shadow: drop, shadowY: 2.5)
    static let title = LabStyle(font: rounded(30, .black), shadow: drop, shadowY: 2.5)
    static let headline = LabStyle(font: rounded(22, .black), shadow: drop, shadowY: 2.5)
    static let cardTitle = LabStyle(font: rounded(17, .heavy))
    static let body = LabStyle(font: rounded(16, .semibold))
    static let label = LabStyle(font: rounded(14, .heavy))
    static let caption = LabStyle(font: rounded(12, .bold))
    static let eyebrow = LabStyle(font: rounded(12, .heavy), tracking: 1.4)
}
