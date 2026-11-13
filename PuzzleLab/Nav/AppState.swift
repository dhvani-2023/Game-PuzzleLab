import SwiftUI
import Observation

/// Screens pushed over the tab shell. Cases keep the Kotlin names: `Route.Play(gameID, level)`.
enum Route: Hashable {
    /// Level map of a game.
    case Levels(String)
    /// A level of a game.
    case Play(String, Int)
    /// A game's date-seeded daily challenge.
    case Daily(String)
    /// Full-screen settings.
    case Settings
    /// Privacy Policy or Terms & Conditions.
    case Legal(String)

    static func levels(gameID: String) -> Route { .Levels(gameID) }
    static func play(gameID: String, level: Int) -> Route { .Play(gameID, level) }
    static func daily(gameID: String) -> Route { .Daily(gameID) }
    static func legal(doc: String) -> Route { .Legal(doc) }
    static var settings: Route { .Settings }

    /// A stable key for transitions (Kotlin `toString()`).
    var key: String {
        switch self {
        case .Levels(let id): return "Levels(\(id))"
        case .Play(let id, let level): return "Play(\(id),\(level))"
        case .Daily(let id): return "Daily(\(id))"
        case .Settings: return "Settings"
        case .Legal(let doc): return "Legal(\(doc))"
        }
    }
}

/// The app shell's sections, in the bottom bar.
enum AppTab: String, CaseIterable {
    case Home, Games, Progress, Settings

    var title: String { rawValue }

    var icon: ImageVector {
        switch self {
        case .Home: return Icons.Rounded.Home
        case .Games: return Icons.Rounded.GridView
        case .Progress: return Icons.Rounded.BarChart
        case .Settings: return Icons.Rounded.Settings
        }
    }

    static var entries: [AppTab] { allCases }
}

/// Screens pushed over the tab shell, plus the selected tab.
@Observable
final class Router {
    var stack: [Route] = []
    var tab: AppTab = .Home
    /// Bumped on every push, so the incoming screen can pick its entrance.
    private(set) var pushCount = 0
    /// Whether the last stack change went deeper (push) or back (pop); read by the route transition.
    @ObservationIgnored private(set) var lastForward = true

    var top: Route? { stack.last }

    func push(_ route: Route) {
        lastForward = true
        stack.append(route)
        pushCount += 1
    }

    @discardableResult
    func pop() -> Bool {
        if stack.isEmpty { return false }
        lastForward = false
        stack.removeLast()
        return true
    }

    func replaceAll(_ routes: [Route]) {
        lastForward = routes.count >= stack.count
        stack = routes
        pushCount += 1
    }

    /// Plays the next level of a game, or opens its map once every level is done.
    func play(_ module: any GameModule, _ store: ProgressStore) {
        UISound.whoosh()
        let progress = store.progress(module.info.id)
        if progress.isComplete { push(.Levels(module.info.id)) } else { push(.Play(module.info.id, progress.currentLevel)) }
    }

    func openLevels(_ module: any GameModule) {
        UISound.whoosh()
        push(.Levels(module.info.id))
    }

    /// From a play screen: back to the game's map (pops to it if it's underneath).
    func backToLevels(_ gameID: String) {
        lastForward = false
        if let index = stack.lastIndex(of: .Levels(gameID)) {
            if stack.count > index + 1 { stack.removeSubrange((index + 1)...) }
        } else {
            stack = [.Levels(gameID)]
            pushCount += 1
        }
    }
}

/// Everything the screens share, created once per process. Injected with `.environment(AppState.shared)`
/// and read with `@Environment(AppState.self)` (or `LocalApp.current` from plain code).
@Observable
final class AppState {
    static let shared = AppState(AppSettings(), PlayerProfile())

    let settings: AppSettings
    let profile: PlayerProfile
    let store: ProgressStore
    let router = Router()
    /// Settings keeps its place when a legal page opens over it and closes again.
    @ObservationIgnored var settingsScroll: CGFloat = 0

    init(_ settings: AppSettings, _ profile: PlayerProfile) {
        self.settings = settings
        self.profile = profile
        store = ProgressStore(GameRegistry.games.map { ($0.info.id, $0.info.levelCount) })
    }
}

/// Kotlin `LocalApp.current`.
enum LocalApp {
    static var current: AppState { AppState.shared }
}
