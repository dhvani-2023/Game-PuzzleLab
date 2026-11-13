import Foundation

/// Every game in the app, in display order.
enum GameRegistry {
    static let games: [any GameModule] = [
        PatchesModule.shared,
        ZipModule.shared,
        TileBurstModule.shared,
        ArrowJamModule.shared,
        BoxBattleModule.shared,
    ]

    /// The newest game: headlines home (Today's pick) for its first week on the device.
    static let SPOTLIGHT_ID = "boxbattle"

    private static let byID: [String: any GameModule] = {
        var map: [String: any GameModule] = [:]
        for g in games { map[g.info.id] = g }
        return map
    }()

    static func game(_ id: String) -> (any GameModule)? { byID[id] }

    /// A literal sum of `GameInfo.levelCount` (never parses a pack).
    static var totalLevels: Int { games.reduce(0) { $0 + $1.info.levelCount } }

    private static var preloaded = false
    private static let lock = NSLock()

    /// Decodes every level pack off the main thread, so maps and games open instantly.
    static func preloadInBackground() {
        lock.lock()
        if preloaded { lock.unlock(); return }
        preloaded = true
        lock.unlock()
        for m in games {
            DispatchQueue.global(qos: .userInitiated).async { m.preload() }
        }
    }
}
