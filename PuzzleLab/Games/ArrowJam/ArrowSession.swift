import Foundation
import Observation
import QuartzCore

/// Seconds on the monotonic clock (Android `SystemClock.uptimeMillis() / 1000.0`); the board's
/// display link uses the same time base.
func nowSeconds() -> Double { CACurrentMediaTime() }

/// Coins for Arrow Jam, earned by winning and spent on tools.
@Observable
final class ArrowBank {
    static let HINT_COST = 40
    static let HAMMER_COST = 120
    static let REVIVE_COST = 100
    static let SKIP_COST = 200
    private static let KEY = "progress.arrowjam.coins"

    /// The observable balance (SwiftUI views that read `ArrowBank.coins` update when it changes).
    static let state = ArrowBank()
    private(set) var value = -1

    private init() {}

    static var coins: Int { state.value }

    static func load() {
        if state.value < 0 { state.value = Prefs.contains(KEY) ? Prefs.int(KEY) : 200 }
    }

    static func earn(_ amount: Int) {
        load()
        if amount <= 0 { return }
        state.value += amount
        Prefs.putInt(KEY, state.value)
    }

    static func spend(_ amount: Int) -> Bool {
        load()
        if state.value < amount { return false }
        state.value -= amount
        Prefs.putInt(KEY, state.value)
        return true
    }
}

/// Free tools, failed attempts and the daily streak.
enum ArrowRecords {
    static let FREE_HINTS_PER_DAY = 3

    static func day() -> Int { Days.dayNumber() }

    static var freeHintsLeft: Int {
        Prefs.int("progress.arrowjam.hints.day") == day()
            ? max(0, FREE_HINTS_PER_DAY - Prefs.int("progress.arrowjam.hints.used")) : FREE_HINTS_PER_DAY
    }

    static func useFreeHint() {
        if Prefs.int("progress.arrowjam.hints.day") != day() {
            Prefs.putInt("progress.arrowjam.hints.day", day())
            Prefs.putInt("progress.arrowjam.hints.used", 0)
        }
        Prefs.putInt("progress.arrowjam.hints.used", Prefs.int("progress.arrowjam.hints.used") + 1)
    }

    /// Worlds whose free hammer is used, in the order they were used (Kotlin `toSet()` keeps order).
    private static func hammerWorlds() -> [Int] {
        guard let raw = Prefs.string("progress.arrowjam.hammer.worlds") else { return [] }
        var out: [Int] = []
        for part in raw.split(separator: ",", omittingEmptySubsequences: false) {
            if let v = Int(part), !out.contains(v) { out.append(v) }
        }
        return out
    }

    /// One free hammer per world of 100 levels.
    static func hasFreeHammer(_ world: Int) -> Bool { !hammerWorlds().contains(world) }

    static func useFreeHammer(_ world: Int) {
        var worlds = hammerWorlds()
        if !worlds.contains(world) { worlds.append(world) }
        Prefs.putString("progress.arrowjam.hammer.worlds", worlds.map(String.init).joined(separator: ","))
    }

    static func fails(_ level: Int) -> Int { Prefs.int("progress.arrowjam.fails.\(level)") }
    static func addFail(_ level: Int) { Prefs.putInt("progress.arrowjam.fails.\(level)", fails(level) + 1) }
    static func clearFails(_ level: Int) { Prefs.remove("progress.arrowjam.fails.\(level)") }

    /// Today's board in the daily pack (the same for everyone on a given date).
    static func dailyLevelID(_ count: Int) -> Int { count > 0 ? ((day() % count) + count) % count + 1 : 1 }

    static var dailyStreak: Int {
        let last = Prefs.int("progress.arrowjam.daily.lastDay")
        return last >= day() - 1 ? Prefs.int("progress.arrowjam.daily.streak") : 0
    }

    static var isDailyDone: Bool { Prefs.int("progress.arrowjam.daily.lastDay") == day() }

    /// Counts today toward the streak; returns the new streak.
    @discardableResult
    static func markDailyDone() -> Int {
        let today = day()
        let last = Prefs.int("progress.arrowjam.daily.lastDay")
        if last == today { return dailyStreak }
        let streak = last == today - 1 ? Prefs.int("progress.arrowjam.daily.streak") + 1 : 1
        Prefs.putInt("progress.arrowjam.daily.streak", streak)
        Prefs.putInt("progress.arrowjam.daily.lastDay", today)
        return streak
    }
}

/// A short animation on one arrow, drawn by the board's effects layer.
final class ArrowEffect {
    enum Kind: Equatable {
        case Exit(travel: Double)
        case Bump(distance: Int)
        case Smash
        case Lane
    }

    let id: Int
    let arrow: Int
    let kind: Kind
    let start: Double
    let duration: Double

    init(_ id: Int, _ arrow: Int, _ kind: Kind, _ start: Double, _ duration: Double) {
        self.id = id
        self.arrow = arrow
        self.kind = kind
        self.start = start
        self.duration = duration
    }

    func progress(_ t: Double) -> Double { min(max((t - start) / duration, 0), 1) }
    func isActive(_ t: Double) -> Bool { t < start + duration }
    var hidesArrow: Bool { kind != .Lane }
}

/// One play of an Arrow Jam board: hearts, combo, tools, animations and saving.
@MainActor
@Observable
final class ArrowJamSession {
    enum Mode { case Adventure, Daily }
    enum Phase { case Playing, Won, Lost }

    static let MAX_HEARTS = 3
    static let COMBO_WINDOW = 1.2
    static func entranceDuration(_ count: Int) -> Double { 0.55 + min(Double(count) * 0.008, 0.55) }

    let mode: Mode
    let level: ArrowLevel
    let reduceMotion: Bool

    private(set) var board: ArrowBoard
    /// Bumped whenever an arrow leaves, so the static layer redraws.
    private(set) var boardRevision = 0
    private(set) var phase: Phase = .Playing
    private(set) var hearts = ArrowJamSession.MAX_HEARTS
    private(set) var heartsLost = 0
    private(set) var combo = 0
    @ObservationIgnored private(set) var bestCombo = 0
    @ObservationIgnored private(set) var comboStart: Double?
    @ObservationIgnored private(set) var coinsEarned = 0
    @ObservationIgnored private(set) var hintsUsed = 0
    @ObservationIgnored private let startedAt = nowSeconds()
    var hammerArmed = false

    @ObservationIgnored let entranceStart = nowSeconds()
    private(set) var effects: [ArrowEffect] = []
    private(set) var hint: (first: Int, second: Double)?
    private(set) var aiming: Int?
    private(set) var inEntrance = true
    private(set) var replaying = false
    @ObservationIgnored private var nextEffectID = 0

    private(set) var exitTick = 0
    private(set) var bumpTick = 0
    private(set) var hammerTick = 0
    private(set) var hintTick = 0
    private(set) var resultTick = 0

    /// Coroutines of this session (Kotlin's composition scope); cancelled by `dispose()`.
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    var total: Int { board.pieces.count }
    var cleared: Int { _ = boardRevision; return total - board.remaining }
    var stars: Int { Scoring.stars(heartsLost) }
    var elapsedSeconds: Int { min(3600, Int(nowSeconds() - startedAt)) }

    init(_ mode: Mode, _ level: ArrowLevel, _ reduceMotion: Bool, _ savedState: String?) {
        self.mode = mode
        self.level = level
        self.reduceMotion = reduceMotion
        board = ArrowBoard(level)
        if let savedState, let o = JSONObject(string: savedState) {
            if let a = o.optJSONArray("r") {
                for i in 0..<a.length() { board.remove(a.getInt(i)) }
            }
            hearts = min(max(o.optInt("h", ArrowJamSession.MAX_HEARTS), 1), ArrowJamSession.MAX_HEARTS)
            heartsLost = o.optInt("l")
            bestCombo = o.optInt("c")
        }
        let entrance = reduceMotion ? 0.25 : ArrowJamSession.entranceDuration(level.a.count)
        launch(after: entrance) { s in s.inEntrance = false }
    }

    /// Stops the session's pending timers (the screen left or loaded another board).
    func dispose() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        replaying = false
    }

    /// `scope.launch { delay(seconds); body() }` on the main actor.
    private func launch(after seconds: Double, _ body: @escaping @MainActor (ArrowJamSession) -> Void) {
        let ns = UInt64(max(0, (seconds * 1000).rounded(.towardZero))) * 1_000_000
        let task = Task { @MainActor [weak self] in
            if ns > 0 { try? await Task.sleep(nanoseconds: ns) }
            guard !Task.isCancelled, let self else { return }
            body(self)
        }
        tasks.removeAll { $0.isCancelled }
        tasks.append(task)
    }

    /// Delay before arrow `index` starts its fly-in.
    func entranceDelay(_ index: Int) -> Double { reduceMotion ? 0 : min(Double(index) * 0.008, 0.55) }

    /// True while anything on the board moves, so the effects layer redraws.
    func animating(_ t: Double) -> Bool {
        inEntrance || aiming != nil || (hint?.second ?? 0) > t || effects.contains { $0.isActive(t) } || combo >= 2
    }

    // MARK: Play

    func fire(_ arrow: Int) {
        if phase != .Playing || hearts <= 0 || replaying || arrow < 0 || arrow >= board.pieces.count || !board.alive[arrow] { return }
        if hammerArmed { smash(arrow); return }
        switch board.tap(arrow) {
        case .Exited:
            boardRevision += 1
            let now = nowSeconds()
            if let cs = comboStart, now - cs < ArrowJamSession.COMBO_WINDOW, combo > 0 { combo += 1 } else { combo = 1 }
            comboStart = now
            bestCombo = max(bestCombo, combo)
            exitTick += 1
            if hint?.first == arrow { hint = nil }
            ArrowSound.play(.Free(min(combo - 1, 10)))
            let duration = addExit(arrow)
            if level.id <= 30 && mode == .Adventure && !reduceMotion { addEffect(arrow, .Lane, 0.45) }
            if board.isCleared { finish(duration) }
        case let .Blocked(_, distance):
            combo = 0
            comboStart = nil
            bumpTick += 1
            hearts -= 1
            heartsLost += 1
            ArrowSound.play(.Bump)
            let duration = reduceMotion ? 0.35 : 0.7
            addEffect(arrow, .Bump(distance: distance), duration)
            launch(after: 0.16) { _ in ArrowSound.play(.Heart) }
            if hearts <= 0 { lose(duration) }
        case .None:
            break
        }
    }

    private func smash(_ arrow: Int) {
        hammerArmed = false
        board.remove(arrow)
        boardRevision += 1
        hammerTick += 1
        combo = 0
        if hint?.first == arrow { hint = nil }
        ArrowSound.play(.Hammer)
        let duration = reduceMotion ? 0.3 : 0.75
        addEffect(arrow, .Smash, duration)
        if board.isCleared { finish(duration) }
    }

    @discardableResult
    private func addExit(_ arrow: Int) -> Double {
        let piece = board.pieces[arrow]
        let travel = Double(board.laneLength(arrow) + piece.cells.count + 3)
        let duration = reduceMotion ? 0.22 : min(0.95, 0.42 + travel * 0.006)
        addEffect(arrow, .Exit(travel: travel), duration)
        return duration
    }

    private func addEffect(_ arrow: Int, _ kind: ArrowEffect.Kind, _ duration: Double) {
        let now = nowSeconds()
        nextEffectID += 1
        effects = effects.filter { $0.isActive(now) } + [ArrowEffect(nextEffectID, arrow, kind, now, duration)]
    }

    func setAim(_ arrow: Int?) {
        if aiming == arrow { return }
        aiming = arrow
        if arrow != nil { ArrowSound.play(.Aim) }
    }

    func comboTimeLeft(_ now: Double) -> Float {
        guard let cs = comboStart else { return 0 }
        if combo < 2 { return 0 }
        return Float(max(0.0, 1 - (now - cs) / ArrowJamSession.COMBO_WINDOW))
    }

    // MARK: Tools

    var hintPriceLabel: String { ArrowRecords.freeHintsLeft > 0 ? "\(ArrowRecords.freeHintsLeft)" : "\(ArrowBank.HINT_COST)" }
    var hammerIsFree: Bool { ArrowRecords.hasFreeHammer(level.world) }

    /// Highlights the best free arrow for 3 s. Returns false when the player can't pay.
    @discardableResult
    func useHint(_ free: Bool = false) -> Bool {
        if phase != .Playing { return false }
        guard let arrow = board.bestHint() else { return false }
        if !free {
            if ArrowRecords.freeHintsLeft > 0 { ArrowRecords.useFreeHint() } else if !ArrowBank.spend(ArrowBank.HINT_COST) { return false }
            hintsUsed += 1
        }
        showHint(arrow)
        return true
    }

    func showHint(_ arrow: Int) {
        hint = (arrow, nowSeconds() + 3)
        hintTick += 1
        ArrowSound.play(.Hint)
    }

    /// Arms (or disarms) the hammer; the next tapped arrow is smashed. Paid for on arming.
    func toggleHammer() -> Bool {
        if hammerArmed { hammerArmed = false; return true }
        if phase != .Playing { return false }
        if ArrowRecords.hasFreeHammer(level.world) { ArrowRecords.useFreeHammer(level.world) } else if !ArrowBank.spend(ArrowBank.HAMMER_COST) { return false }
        hammerArmed = true
        ArrowSound.play(.Aim)
        return true
    }

    func revive() -> Bool {
        if phase != .Lost || !ArrowBank.spend(ArrowBank.REVIVE_COST) { return false }
        hearts = ArrowJamSession.MAX_HEARTS
        phase = .Playing
        ArrowSound.play(.Revive)
        return true
    }

    // MARK: End

    private func finish(_ delaySeconds: Double) {
        launch(after: delaySeconds * 0.9) { s in
            if s.phase != .Playing { return }
            s.coinsEarned = s.coins()
            s.phase = .Won
            s.resultTick += 1
            ArrowSound.play(.Win)
        }
    }

    private func lose(_ delaySeconds: Double) {
        launch(after: delaySeconds) { s in
            if s.phase != .Playing || s.hearts > 0 { return }
            s.phase = .Lost
            if s.mode == .Adventure { ArrowRecords.addFail(s.level.id) }
            ArrowSound.play(.Lose)
        }
    }

    /// Stars, combo bonus, milestones and the daily bonus.
    func coins() -> Int {
        var c = [0, 10, 20, 30][stars] + min(15, max(0, bestCombo - 3))
        c += mode == .Adventure ? (level.id % 25 == 0 ? 50 : 0) : 40
        return c
    }

    var snapshot: String? {
        if phase != .Playing || cleared == 0 { return nil }
        let removed = board.alive.indices.filter { !board.alive[$0] }
        return "{\"r\":[\(removed.map(String.init).joined(separator: ","))],\"h\":\(hearts),\"l\":\(heartsLost),\"c\":\(bestCombo)}"
    }

    /// Rebuilds the board and plays the solution, every arrow leaving in turn.
    func playReplay() {
        if phase != .Won || replaying { return }
        let fresh = ArrowBoard(level)
        guard let order = fresh.solutionOrder() else { return }
        board = fresh
        boardRevision += 1
        replaying = true
        effects = []
        inEntrance = false
        let step = min(0.07, 4.0 / Double(max(order.count, 1)))
        let stepNs = UInt64(max(0, (step * 1000).rounded(.towardZero))) * 1_000_000
        let task = Task { @MainActor [weak self] in
            for (index, arrow) in order.enumerated() {
                guard let s = self, s.replaying, !Task.isCancelled else { return }
                s.board.remove(arrow)
                s.boardRevision += 1
                s.addExit(arrow)
                if index % 4 == 0 { ArrowSound.play(.Free((index / 4) % 11)) }
                try? await Task.sleep(nanoseconds: stepNs)
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            self?.replaying = false
        }
        tasks.append(task)
    }
}
