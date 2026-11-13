import SwiftUI

/// Static description of a game, cheap to read (no level pack loading).
struct GameInfo {
    let id: String
    let name: String
    let tagline: String
    let category: String
    let colors: [Color]
    let levelCount: Int

    init(id: String, name: String, tagline: String, category: String, colors: [Color], levelCount: Int) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.category = category
        self.colors = colors
        self.levelCount = levelCount
    }

    /// Compose `Brush.linearGradient(colors)`: top-left → bottom-right.
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
    var first: Color { colors.first ?? .white }
    var last: Color { colors.last ?? .white }
}

struct HowToPlayStep {
    let icon: ImageVector
    let title: String
    let message: String

    init(icon: ImageVector, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    init(_ icon: ImageVector, _ title: String, _ message: String) {
        self.init(icon: icon, title: title, message: message)
    }
}

/// A date-seeded challenge shown in home's Daily row.
struct DailyChallenge {
    let title: String
    let detail: String
    let streak: Int
    let isDone: Bool

    init(title: String, detail: String, streak: Int, isDone: Bool) {
        self.title = title
        self.detail = detail
        self.streak = streak
        self.isDone = isDone
    }

    init(_ title: String, _ detail: String, _ streak: Int, _ isDone: Bool) {
        self.init(title: title, detail: detail, streak: streak, isDone: isDone)
    }
}

/// How a game's journey map looks: its worlds (level ranges with their own backdrop).
final class LevelMapTheme {
    struct World {
        let name: String
        let range: ClosedRange<Int>
        let top: Color
        let bottom: Color
        let accent: Color
        let motif: ImageVector
        var isDark: Bool = true

        init(name: String, range: ClosedRange<Int>, top: Color, bottom: Color, accent: Color, motif: ImageVector, isDark: Bool = true) {
            self.name = name
            self.range = range
            self.top = top
            self.bottom = bottom
            self.accent = accent
            self.motif = motif
            self.isDark = isDark
        }

        init(_ name: String, _ range: ClosedRange<Int>, _ top: Color, _ bottom: Color, _ accent: Color, _ motif: ImageVector, _ isDark: Bool = true) {
            self.init(name: name, range: range, top: top, bottom: bottom, accent: accent, motif: motif, isDark: isDark)
        }
    }

    let worlds: [World]
    /// The game's coin balance for the map header pill (games with coins only).
    let coins: (() -> Int)?

    init(_ worlds: [World], coins: (() -> Int)? = nil) {
        self.worlds = worlds
        self.coins = coins
    }

    convenience init(worlds: [World], coins: (() -> Int)? = nil) { self.init(worlds, coins: coins) }

    func worldIndex(_ level: Int) -> Int {
        if let i = worlds.firstIndex(where: { $0.range.contains(level) }) { return i }
        return max(0, worlds.count - 1)
    }

    /// One world per difficulty tier, named and coloured from `palettes`; ranges stop at `through`.
    static func tiers(_ catalog: LevelCatalog, _ names: [String], _ palettes: [(Int, Int, Int)], through: Int = Int.max) -> [World] {
        var out: [World] = []
        for (index, tier) in catalog.tiers.enumerated() {
            guard let range = catalog.range(tier) else { continue }
            if range.lowerBound > through { continue }
            let p = palettes[index % palettes.count]
            out.append(World(name: index < names.count ? names[index] : tier.title,
                             range: range.lowerBound...min(range.upperBound, through),
                             top: hex(p.0), bottom: hex(p.1), accent: hex(p.2), motif: tierIcon(tier)))
        }
        return out
    }

    static func tiers(catalog: LevelCatalog, names: [String], palettes: [(Int, Int, Int)], through: Int = Int.max) -> [World] {
        tiers(catalog, names, palettes, through: through)
    }

    /// Splits levels `first…count` into worlds of `size`. Names, palettes and motifs cycle; a repeated
    /// name gets a numeral ("Mint Grove II").
    static func blocks(_ count: Int, _ size: Int, _ names: [String], _ palettes: [(Int, Int, Int)], _ motifs: [ImageVector], first: Int = 1) -> [World] {
        var out: [World] = []
        let n = max(names.count, 1)
        for (index, start) in stride(from: first, through: max(count, first), by: size).enumerated() {
            // Kotlin's `start..minOf(…, count)` is just empty when the pack is missing; a Swift range would trap.
            if start > count { continue }
            let p = palettes[index % palettes.count]
            let base = names.isEmpty ? "World \(index + 1)" : names[index % n]
            out.append(World(name: lapName(base, index / n), range: start...min(start + size - 1, count),
                             top: hex(p.0), bottom: hex(p.1), accent: hex(p.2), motif: motifs[index % motifs.count]))
        }
        return out
    }

    static func blocks(count: Int, size: Int, names: [String], palettes: [(Int, Int, Int)], motifs: [ImageVector], first: Int = 1) -> [World] {
        blocks(count, size, names, palettes, motifs, first: first)
    }
}

/// A world name on its `lap`-th repeat: "Mint Grove", "Mint Grove II", "Mint Grove III"…
func lapName(_ name: String, _ lap: Int) -> String {
    if lap <= 0 { return name }
    return "\(name) " + String(repeating: "I", count: lap + 1).replacingOccurrences(of: "IIII", with: "IV")
}

func tierIcon(_ tier: DifficultyTier) -> ImageVector {
    switch tier {
    case .Easy: return Icons.Rounded.Eco
    case .Medium: return Icons.Rounded.LocalFireDepartment
    case .Hard: return Icons.Rounded.Bolt
    case .Expert: return Icons.Rounded.EmojiEvents
    case .Master: return Icons.Rounded.Diamond
    }
}

func tierColor(_ tier: DifficultyTier, _ lab: LabPalette) -> Color { lab.patch(tier.patchIndex) }

/// The SF Symbols the iOS map themes used (Android mapped them to Material equivalents).
enum Motifs {
    static let moon = "moon.stars.fill"
    static let waves = "water.waves"
    static let sunset = "sunset.fill"
    static let leaf = "leaf.fill"
    static let cloud = "cloud.fill"
    static let sun = "sun.max.fill"
    static let snow = "snowflake"
    static let flame = "flame.fill"
    static let game = "gamecontroller.fill"
    static let sparkles = "sparkles"
    static let boat = "sailboat.fill"
    static let tree = "tree.fill"
    static let mountain = "mountain.2.fill"
    static let bolt = "bolt.fill"
    static let crown = "crown.fill"
}

/// A playable game. Everything game-specific lives behind this protocol; the shared home, level map,
/// play shell, progress and win flow work for any module.
///
/// Implement as `final class XModule: GameModule { static let shared = XModule() … }` (GameRegistry lists
/// `XModule.shared`). The view builders return `AnyView`, e.g. `AnyView(PinwheelLogo(size * 0.82))`.
protocol GameModule {
    var info: GameInfo { get }
    var catalog: LevelCatalog { get }
    var howToPlay: [HowToPlayStep] { get }
    var mapTheme: LevelMapTheme { get }
    /// Today's date-seeded challenge, if the game has one.
    var daily: DailyChallenge? { get }

    /// Decodes the level pack(s) now; called off the main thread.
    func preload()

    /// The game's own art for its badge (a `size`×`size` square), drawn on top of the gradient.
    @MainActor func BadgeArt(_ size: CGFloat) -> AnyView

    /// Animated illustration for showcase and onboarding cards; fills the space it is given.
    @MainActor func Artwork() -> AnyView

    @MainActor func PlayScreen(_ level: Int) -> AnyView

    @MainActor func DailyScreen() -> AnyView
}

extension GameModule {
    var daily: DailyChallenge? { nil }
    @MainActor func DailyScreen() -> AnyView { AnyView(EmptyView()) }
}
