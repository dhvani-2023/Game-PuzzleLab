import Foundation

/// Difficulty bands shared by every game's level pack (`"tier"` in the JSON).
enum DifficultyTier: String, CaseIterable, Hashable {
    case Easy, Medium, Hard, Expert, Master

    var title: String { rawValue }

    var patchIndex: Int {
        switch self {
        case .Easy: return 3
        case .Medium: return 5
        case .Hard: return 1
        case .Expert: return 7
        case .Master: return 6
        }
    }

    static var entries: [DifficultyTier] { allCases }

    static func parse(_ raw: String) -> DifficultyTier {
        allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame } ?? .Easy
    }

    // Swift-style spellings.
    static let easy = DifficultyTier.Easy
    static let medium = DifficultyTier.Medium
    static let hard = DifficultyTier.Hard
    static let expert = DifficultyTier.Expert
    static let master = DifficultyTier.Master
}

/// A level as stored in a game's bundled JSON pack. Ids run 1…count.
protocol PackLevel {
    var id: Int { get }
    var tier: DifficultyTier { get }
    /// Short size label shown in level lists, e.g. "7×7".
    var sizeLabel: String { get }
}

/// What the shared screens need to know about a game's levels, without knowing the level type.
protocol LevelCatalog: AnyObject {
    var version: Int { get }
    var count: Int { get }
    var tiers: [DifficultyTier] { get }
    func tier(_ level: Int) -> DifficultyTier?
    func range(_ tier: DifficultyTier) -> ClosedRange<Int>?
    func sizeLabel(_ level: Int) -> String
}

/// A decoded level pack, read from `Levels/<resource>.json` the first time it's needed (thread-safe,
/// decoded once; call `preload()` off the main thread to warm it up).
final class LevelPack<L: PackLevel>: LevelCatalog, @unchecked Sendable {
    private struct Loaded {
        let version: Int
        let levels: [L]
        let ranges: [DifficultyTier: ClosedRange<Int>]
    }

    private let resource: String
    private let parse: (JSONObject) -> L
    private let lock = NSLock()
    private var loaded: Loaded?

    init(_ resource: String, _ parse: @escaping (JSONObject) -> L) {
        self.resource = resource
        self.parse = parse
    }

    private var data: Loaded {
        lock.lock()
        defer { lock.unlock() }
        if let loaded { return loaded }
        let l = load()
        loaded = l
        return l
    }

    private func load() -> Loaded {
        guard let url = LevelPackFiles.url(resource),
              let bytes = try? Data(contentsOf: url, options: .mappedIfSafe),
              let root = JSONObject(data: bytes)
        else {
            assertionFailure("Missing level pack \(resource).json")
            return Loaded(version: 1, levels: [], ranges: [:])
        }
        let array = root.getJSONArray("levels")
        var levels: [L] = []
        levels.reserveCapacity(array.length())
        for i in 0..<array.length() { levels.append(parse(array.getJSONObject(i))) }
        levels.sort { $0.id < $1.id }
        var ranges: [DifficultyTier: ClosedRange<Int>] = [:]
        for level in levels {
            if let current = ranges[level.tier] {
                ranges[level.tier] = min(current.lowerBound, level.id)...max(current.upperBound, level.id)
            } else {
                ranges[level.tier] = level.id...level.id
            }
        }
        return Loaded(version: root.optInt("version", 1), levels: levels, ranges: ranges)
    }

    /// Decodes the pack now (call off the main thread to warm it up).
    func preload() { _ = data }

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loaded != nil
    }

    var levels: [L] { data.levels }
    var version: Int { data.version }
    var count: Int { data.levels.count }
    var tiers: [DifficultyTier] { let r = data.ranges; return DifficultyTier.allCases.filter { r[$0] != nil } }

    func level(_ id: Int) -> L? {
        let all = data.levels
        return id >= 1 && id <= all.count ? all[id - 1] : nil
    }

    func tier(_ level: Int) -> DifficultyTier? { self.level(level)?.tier }
    func range(_ tier: DifficultyTier) -> ClosedRange<Int>? { data.ranges[tier] }
    func sizeLabel(_ level: Int) -> String { self.level(level)?.sizeLabel ?? "" }
}

/// Finds a bundled pack (synchronized folders copy resources flat; a `Levels/` folder also works).
enum LevelPackFiles {
    static func url(_ resource: String) -> URL? {
        Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "Levels")
            ?? Bundle.main.url(forResource: resource, withExtension: "json")
            ?? Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "Resources/Levels")
    }
}
