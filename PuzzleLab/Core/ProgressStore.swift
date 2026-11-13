import Foundation
import Observation

struct LevelRecord: Equatable {
    let bestTime: Int
    let stars: Int
    let hintsUsed: Int
}

enum Scoring {
    static func stars(_ hints: Int) -> Int {
        switch hints {
        case 0: return 3
        case 1: return 2
        default: return 1
        }
    }
}

/// Android unlocks levels through "Watch ad" in debug builds only; iOS routes every such unlock through
/// the rewarded-ad seam (`Ads.rewarded`, which grants instantly while no ad network is configured).
let adUnlocksEnabled = true

/// Solves, saved boards and ad-unlocked levels for one game. Each game persists under its own keys
/// (`progress.<id>.records`, `.saved`, `.adUnlocked`), the same keys the Android and iOS apps use.
@Observable
final class GameProgress {
    let gameID: String
    let levelCount: Int

    /// Read by every getter, so views re-read progress whenever it changes.
    private(set) var revision = 0

    @ObservationIgnored private var records: [Int: LevelRecord] = [:]
    @ObservationIgnored private var saved: [Int: (version: Int, data: String)] = [:]
    @ObservationIgnored private var adUnlocked = Set<Int>()
    @ObservationIgnored private var cachedCurrent = 1
    @ObservationIgnored private var cachedStars = 0

    private var recordsKey: String { "progress.\(gameID).records" }
    private var savedKey: String { "progress.\(gameID).saved" }
    private var unlockedKey: String { "progress.\(gameID).adUnlocked" }

    init(_ gameID: String, _ levelCount: Int) {
        self.gameID = gameID
        self.levelCount = levelCount
        load()
    }

    private func load() {
        records.removeAll(); saved.removeAll(); adUnlocked.removeAll()
        if let raw = Prefs.string(recordsKey), let o = JSONObject(string: raw) {
            for k in o.keys() {
                guard let level = Int(k) else { continue }
                let r = o.getJSONObject(k)
                records[level] = LevelRecord(bestTime: r.optInt("t"), stars: r.optInt("s"), hintsUsed: r.optInt("h"))
            }
        }
        if let raw = Prefs.string(savedKey), let o = JSONObject(string: raw) {
            for k in o.keys() {
                guard let level = Int(k) else { continue }
                let r = o.getJSONObject(k)
                saved[level] = (r.optInt("v"), r.optString("d"))
            }
        }
        if let raw = Prefs.string(unlockedKey), let a = JSONArray(string: raw) {
            for i in 0..<a.length() { adUnlocked.insert(a.getInt(i)) }
        }
        recompute()
    }

    var solvedCount: Int { _ = revision; return records.count }
    var isComplete: Bool { _ = revision; return levelCount > 0 && records.count >= levelCount }
    /// First unsolved level (or the last level once everything is solved).
    var currentLevel: Int { _ = revision; return cachedCurrent }
    var totalStars: Int { _ = revision; return cachedStars }

    func record(_ level: Int) -> LevelRecord? { _ = revision; return records[level] }
    func isSolved(_ level: Int) -> Bool { _ = revision; return records[level] != nil }
    func isAdUnlocked(_ level: Int) -> Bool { _ = revision; return adUnlocksEnabled && adUnlocked.contains(level) }

    func solvedCount(_ range: ClosedRange<Int>) -> Int {
        _ = revision
        var n = 0
        for l in range where records[l] != nil { n += 1 }
        return n
    }

    func stars(_ range: ClosedRange<Int>) -> Int {
        _ = revision
        var n = 0
        for l in range { n += records[l]?.stars ?? 0 }
        return n
    }

    /// Levels unlock one after another, or early through the rewarded "jump ahead" offer.
    func isUnlocked(_ level: Int) -> Bool {
        _ = revision
        return level <= cachedCurrent || records[level] != nil || (adUnlocksEnabled && adUnlocked.contains(level))
    }

    /// "Watch ad to play": opens a level ahead of the player's progress.
    func unlockWithAd(_ level: Int) {
        guard adUnlocksEnabled else { return }
        if adUnlocked.insert(level).inserted {
            Prefs.putString(unlockedKey, JSONArray(values: adUnlocked.sorted()).toString())
            revision += 1
        }
    }

    func savedState(_ level: Int, _ packVersion: Int) -> String? {
        guard let s = saved[level], s.version == packVersion else { return nil }
        return s.data
    }

    func saveState(_ data: String?, _ level: Int, _ packVersion: Int) {
        if let data { saved[level] = (packVersion, data) } else { saved[level] = nil }
        storeSaved()
    }

    /// Keeps the best time and star count; returns true when an earlier time was beaten.
    @discardableResult
    func storeSolve(_ level: Int, _ time: Int, _ hintsUsed: Int, _ stars: Int) -> Bool {
        let previous = records[level]
        records[level] = LevelRecord(
            bestTime: min(time, previous?.bestTime ?? time),
            stars: max(stars, previous?.stars ?? 0),
            hintsUsed: min(hintsUsed, previous?.hintsUsed ?? hintsUsed)
        )
        saved[level] = nil
        storeRecords(); storeSaved()
        recompute()
        if let previous { return time < previous.bestTime }
        return false
    }

    func reset() {
        records.removeAll(); saved.removeAll(); adUnlocked.removeAll()
        Prefs.remove(recordsKey); Prefs.remove(savedKey); Prefs.remove(unlockedKey)
        recompute()
    }

    private func recompute() {
        if levelCount > 0 {
            var first = levelCount
            for l in 1...levelCount where records[l] == nil { first = l; break }
            cachedCurrent = first
        } else {
            cachedCurrent = 1
        }
        cachedStars = records.values.reduce(0) { $0 + $1.stars }
        revision += 1
    }

    private func storeRecords() {
        var o = JSONObject()
        for (k, r) in records.sorted(by: { $0.key < $1.key }) {
            o.put(String(k), JSONObject().putting("t", r.bestTime).putting("s", r.stars).putting("h", r.hintsUsed))
        }
        Prefs.putString(recordsKey, o.toString())
    }

    private func storeSaved() {
        var o = JSONObject()
        for (k, v) in saved.sorted(by: { $0.key < $1.key }) {
            o.put(String(k), JSONObject().putting("v", v.version).putting("d", v.data))
        }
        Prefs.putString(savedKey, o.toString())
    }
}

/// All progress: one `GameProgress` per game plus player-wide stats (streak, play days, Lab Tour).
@Observable
final class ProgressStore {
    private struct Stats {
        var streak = 0
        var lastSolveDay: Int?
        var lastPlayedGameID: String?
        var bestStreak = 0
        var playDays: [Int] = []
        var tourDay: Int?
        var tourGames: [String] = []
        var toursDone = 0
    }

    @ObservationIgnored private let gameIDs: [String]
    @ObservationIgnored private let games: [String: GameProgress]
    @ObservationIgnored private var stats: Stats
    private var revision = 0

    @ObservationIgnored private static let statsKey = "player.stats.v1"

    init(_ games: [(String, Int)]) {
        gameIDs = games.map { $0.0 }
        var map: [String: GameProgress] = [:]
        for (id, count) in games { map[id] = GameProgress(id, count) }
        self.games = map
        stats = Self.loadStats()
    }

    func progress(_ gameID: String) -> GameProgress {
        if let p = games[gameID] { return p }
        preconditionFailure("Unknown game \(gameID)")
    }

    private var allProgress: [GameProgress] { gameIDs.compactMap { games[$0] } }

    var lastPlayedGameID: String? { _ = revision; return stats.lastPlayedGameID }
    var totalSolved: Int { allProgress.reduce(0) { $0 + $1.solvedCount } }
    var totalStars: Int { allProgress.reduce(0) { $0 + $1.totalStars } }

    /// Days in a row with at least one solve; 0 once a day is missed.
    var streak: Int {
        _ = revision
        guard let last = stats.lastSolveDay else { return 0 }
        return Days.dayNumber() - last <= 1 ? stats.streak : 0
    }

    var bestStreak: Int { max(stats.bestStreak, streak) }

    func didPlay(_ day: Int) -> Bool { _ = revision; return stats.playDays.contains(day) }

    func markPlayed(_ gameID: String) {
        markTour(gameID)
        if stats.lastPlayedGameID == gameID { return }
        stats.lastPlayedGameID = gameID
        persist()
    }

    /// Distinct games played today, in the order they were first played.
    var tourGames: [String] {
        _ = revision
        return stats.tourDay == Days.dayNumber() ? stats.tourGames : []
    }

    var tourComplete: Bool { tourGames.count >= LabTour.GOAL }

    private func markTour(_ gameID: String) {
        let today = Days.dayNumber()
        if stats.tourDay != today {
            stats.tourDay = today
            stats.tourGames = []
        }
        if stats.tourGames.contains(gameID) || stats.tourGames.count >= LabTour.GOAL { return }
        stats.tourGames.append(gameID)
        if stats.tourGames.count == LabTour.GOAL { stats.toursDone += 1 }
        persist()
    }

    /// Records a solve and bumps the daily streak; returns true for a new best time.
    @discardableResult
    func recordSolve(_ gameID: String, _ level: Int, _ time: Int, _ hintsUsed: Int, _ stars: Int? = nil) -> Bool {
        let isBest = progress(gameID).storeSolve(level, time, hintsUsed, stars ?? Scoring.stars(hintsUsed))
        let today = Days.dayNumber()
        if let last = stats.lastSolveDay {
            if today - last == 1 { stats.streak += 1 }
            else if today - last > 1 { stats.streak = 1 }
            else { stats.streak = max(stats.streak, 1) }
        } else {
            stats.streak = 1
        }
        stats.lastSolveDay = today
        stats.lastPlayedGameID = gameID
        stats.bestStreak = max(stats.bestStreak, stats.streak)
        if !stats.playDays.contains(today) { stats.playDays.append(today) }
        while stats.playDays.count > 70 { stats.playDays.removeFirst() }
        persist()
        return isBest
    }

    /// Labelled form: `recordSolve(gameID:level:time:hintsUsed:stars:)`.
    @discardableResult
    func recordSolve(gameID: String, level: Int, time: Int, hintsUsed: Int, stars: Int? = nil) -> Bool {
        recordSolve(gameID, level, time, hintsUsed, stars)
    }

    /// XP behind the Lab level shown on home (see `LabLevel`).
    var labXP: Int {
        _ = revision
        return LabLevel.xp(totalSolved, totalStars) + stats.toursDone * LabTour.XP
    }

    func resetAll() {
        for p in allProgress { p.reset() }
        stats = Stats()
        persist()
        for k in Prefs.keys() where k.hasPrefix("progress.") && !k.hasSuffix(".coins") { Prefs.remove(k) }
    }

    /// Clears one game's levels, stars, saved boards and records. Coin balances are kept.
    func resetGame(_ gameID: String) {
        games[gameID]?.reset()
        for k in Prefs.keys() where k.hasPrefix("progress.\(gameID).") && !k.hasSuffix(".coins") { Prefs.remove(k) }
        if stats.lastPlayedGameID == gameID {
            stats.lastPlayedGameID = nil
            persist()
        }
        revision += 1
    }

    private static func loadStats() -> Stats {
        var s = Stats()
        guard let raw = Prefs.string(statsKey), let o = JSONObject(string: raw) else { return s }
        s.streak = o.optInt("streak")
        s.lastSolveDay = o.has("lastSolveDay") ? o.getInt("lastSolveDay") : nil
        let last = o.optString("lastPlayed")
        s.lastPlayedGameID = last.isEmpty ? nil : last
        s.bestStreak = o.optInt("bestStreak")
        if let a = o.optJSONArray("playDays") { for i in 0..<a.length() { s.playDays.append(a.getInt(i)) } }
        s.tourDay = o.has("tourDay") ? o.getInt("tourDay") : nil
        if let a = o.optJSONArray("tourGames") { for i in 0..<a.length() { s.tourGames.append(a.getString(i)) } }
        s.toursDone = o.optInt("toursDone")
        return s
    }

    private func persist() {
        var o = JSONObject()
            .putting("streak", stats.streak)
            .putting("lastPlayed", stats.lastPlayedGameID ?? "")
            .putting("bestStreak", stats.bestStreak)
            .putting("playDays", JSONArray(values: stats.playDays))
            .putting("tourGames", JSONArray(values: stats.tourGames))
            .putting("toursDone", stats.toursDone)
        if let d = stats.lastSolveDay { o.put("lastSolveDay", d) }
        if let d = stats.tourDay { o.put("tourDay", d) }
        Prefs.putString(Self.statsKey, o.toString())
        revision += 1
    }
}

/// "Play 3 different games today" on home.
enum LabTour {
    static let GOAL = 3
    static let XP = 30
}

/// 10 XP per solved level plus 5 per star; level n needs 100 × n^1.3 cumulative XP.
enum LabLevel {
    static func xp(_ solved: Int, _ stars: Int) -> Int { 10 * solved + 5 * stars }

    static func threshold(_ level: Int) -> Int {
        if level <= 1 { return 0 }
        return Int((100 * pow(Double(level - 1), 1.3) + 0.5).rounded(.down))
    }

    static func level(_ xp: Int) -> Int {
        var level = 1
        while threshold(level + 1) <= xp { level += 1 }
        return level
    }

    static func progress(_ xp: Int) -> Float {
        let level = level(xp)
        let low = threshold(level)
        let high = threshold(level + 1)
        return high > low ? Float(xp - low) / Float(high - low) : 0
    }
}

/// Home's choices, kept pure.
enum HomePlanner {
    struct GameState: Equatable {
        let id: String
        let solved: Int
        let isComplete: Bool

        init(_ id: String, _ solved: Int, _ isComplete: Bool) {
            self.id = id
            self.solved = solved
            self.isComplete = isComplete
        }
    }

    /// Today's hero game: a rotation through unfinished games, skipping the most-played one.
    static func todaysPick(_ games: [GameState], _ day: Int, _ spotlight: String? = nil) -> String? {
        if let spotlight, games.contains(where: { $0.id == spotlight && !$0.isComplete }) { return spotlight }
        var pool = games.filter { !$0.isComplete }
        if pool.isEmpty { pool = games }
        if pool.count > 1 {
            // maxByOrNull: the first maximum wins.
            var most: GameState?
            for g in pool where most == nil || g.solved > most!.solved { most = g }
            if let most, most.solved > 0 { pool = pool.filter { $0.id != most.id } }
        }
        if pool.isEmpty { return nil }
        let n = pool.count
        return pool[((day % n) + n) % n].id
    }

    /// Up to three games in progress for the Continue row: the last played first, never the hero.
    static func continueGames(_ games: [GameState], _ hero: String?, _ lastPlayed: String?, _ limit: Int = 3) -> [String] {
        let candidates = games.filter { $0.solved > 0 && !$0.isComplete && $0.id != hero }
        // Stable sort: last played first, then most solved.
        let sorted = candidates.enumerated().sorted { a, b in
            let la = a.element.id == lastPlayed, lb = b.element.id == lastPlayed
            if la != lb { return la }
            if a.element.solved != b.element.solved { return a.element.solved > b.element.solved }
            return a.offset < b.offset
        }
        return sorted.prefix(limit).map { $0.element.id }
    }
}
