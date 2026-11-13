import Foundation
import Observation

/** Coins for Tile Burst, earned by playing and spent on revives. Stored on the device only. */
@Observable
final class TileBank {
    static let shared = TileBank()
    static let REVIVE_COST = 120
    private static let KEY = "progress.tileburst.coins"

    private var value = -1

    static var coins: Int { shared.value }

    static func load() {
        if shared.value < 0 { shared.value = Prefs.sp.contains(KEY) ? Prefs.int(KEY) : 200 }
    }

    static func earn(_ amount: Int) {
        load()
        if amount <= 0 { return }
        shared.value += amount
        Prefs.putInt(KEY, shared.value)
    }

    @discardableResult
    static func spend(_ amount: Int) -> Bool {
        load()
        if shared.value < amount { return false }
        shared.value -= amount
        Prefs.putInt(KEY, shared.value)
        return true
    }
}

/** Best scores and the daily streak. */
enum TileRecords {
    private static let BEST = "progress.tileburst.best"
    private static let STREAK = "progress.tileburst.daily.streak"
    private static let LAST_DAY = "progress.tileburst.daily.lastDay"

    static var classicBest: Int {
        get { Prefs.int(BEST) }
        set { Prefs.putInt(BEST, newValue) }
    }

    static func dailyBest(_ day: Int) -> Int { Prefs.int("progress.tileburst.daily.best.\(day)") }
    static func setDailyBest(_ day: Int, _ score: Int) { Prefs.putInt("progress.tileburst.daily.best.\(day)", score) }

    static var dailyStreak: Int { Prefs.int(STREAK) }

    /** Counts today toward the streak (once per day). */
    static func markDailyDone(_ day: Int) {
        let last = Prefs.int(LAST_DAY)
        if last == day { return }
        let yesterday = Days.ymd(Days.nowMillis() - 86_400_000)
        Prefs.putInt(STREAK, last == yesterday ? dailyStreak + 1 : 1)
        Prefs.putInt(LAST_DAY, day)
    }

    static func isDailyDone(_ day: Int) -> Bool { Prefs.int(LAST_DAY) == day }

    static func day() -> Int { Days.ymd() }

    /** The day's target score: the same for everyone, varying through the week. */
    static func dailyTarget(_ day: Int) -> Int { 1500 + (day % 9) * 250 }
}

/** One run of Tile Burst in any mode: owns the board, the dealer, the tray and the scene. */
@Observable
final class TileBurstSession {
    enum Mode: String, CaseIterable {
        case Adventure, Classic, Daily
        var title: String { rawValue }
        static var entries: [Mode] { allCases }
    }

    enum Phase { case Ready, Playing, NoSpace, Won, Over }
    enum Outcome { case Going, Won, Stuck }

    struct Turn {
        let placement: TilePlacement
        let dealt: [TilePiece]?
        let outcome: Outcome
    }

    let mode: Mode
    let level: TileLevel?
    let day: Int
    let board: TileBoard
    private let dealer: TileDealer
    @ObservationIgnored var tray: [TilePiece?] = [nil, nil, nil]

    private(set) var phase: Phase = .Ready
    var paused = false

    private(set) var score = 0
    let best: Int
    private(set) var combo = 0
    private(set) var graceLeft = TileBoard.COMBO_GRACE
    private(set) var fever = false
    private(set) var rounds = 0
    private(set) var remaining: [Int] = []
    private(set) var goalBumps: [Int] = []
    private(set) var revived = false
    private(set) var passedBest = false
    private(set) var reachedTarget = false
    private(set) var isNewBest = false
    private(set) var stars = 0
    private(set) var coinsEarned = 0
    private(set) var elapsedSeconds = 0
    @ObservationIgnored private var startedAt: Int64 = 0

    // Haptic triggers.
    private(set) var pickTick = 0
    private(set) var placeTick = 0
    private(set) var clearTick = 0
    private(set) var bigTick = 0
    private(set) var invalidTick = 0
    private(set) var feverTick = 0
    private(set) var gemTick = 0
    private(set) var milestoneTick = 0

    @ObservationIgnored private(set) var scene: TileScene!

    init(_ mode: Mode, _ level: TileLevel?, _ reduceMotion: Bool) {
        self.mode = mode
        let lvl = mode == .Adventure ? level : nil
        self.level = lvl
        let today = TileRecords.day()
        day = today
        board = TileBoard(lvl)
        dealer = TileDealer(mode == .Daily ? Int64(today) : Int64.random(in: 1..<Int64.max), lvl?.pressure ?? 0.0, lvl?.gemRate ?? 0.0)
        switch mode {
        case .Adventure: best = 0
        case .Classic: best = TileRecords.classicBest
        case .Daily: best = TileRecords.dailyTarget(today)
        }
        let goals = lvl?.goals ?? []
        for g in goals.indices { remaining.append(board.remaining(g)); goalBumps.append(0) }
        for (k, p) in dealer.deal(board).enumerated() { tray[k] = p }
        rounds = 1
        scene = TileScene(self, board, reduceMotion)
        TileSound.warmUp()
        TileBank.load()
    }

    var dailyTarget: Int { TileRecords.dailyTarget(day) }

    /** The world whose theme the board uses. */
    var world: Int {
        switch mode {
        case .Adventure: return level?.world ?? 0
        case .Classic: return 0
        case .Daily: return 1 + day % 9
        }
    }

    /** 0…1 toward the best (Classic) or the day's target (Daily). */
    var bestProgress: Float {
        best <= 0 ? (score > 0 ? 1 : 0) : min(1, Float(score) / Float(best))
    }

    var isTutorial: Bool { mode == .Adventure && (level?.id ?? 99) <= 5 }

    func start() {
        if phase != .Ready { return }
        phase = .Playing
        startedAt = Days.nowMillis()
        scene.didStart()
    }

    func pause() { if phase == .Playing { paused = true } }
    func resume() { paused = false }

    func place(_ slot: Int, _ origin: Int) -> Turn? {
        if phase != .Playing { return nil }
        guard slot >= 0 && slot < tray.count, let piece = tray[slot] else { return nil }
        guard let placement = board.place(piece, origin) else { return nil }
        tray[slot] = nil
        score = board.score
        combo = placement.combo
        graceLeft = placement.graceLeft
        fever = board.fever
        placeTick += 1
        if placement.lines > 0 { clearTick += 1 }
        if placement.lines >= 2 || placement.perfect { bigTick += 1 }
        if placement.feverStarted { feverTick += 1 }
        if !placement.gems.isEmpty { gemTick += 1 }
        if let goals = level?.goals {
            for (g, goal) in goals.enumerated() where goal.kind != .Collect && remaining[g] != board.remaining(g) {
                remaining[g] = board.remaining(g)
                goalBumps[g] += 1
            }
        }
        if mode == .Classic && best > 0 && score > best && !passedBest { passedBest = true; milestoneTick += 1 }
        if mode == .Daily && score >= dailyTarget && !reachedTarget {
            reachedTarget = true
            milestoneTick += 1
            TileRecords.markDailyDone(day)
        }
        if board.goalsDone { return Turn(placement: placement, dealt: nil, outcome: .Won) }
        var dealt: [TilePiece]? = nil
        if tray.allSatisfy({ $0 == nil }) {
            if mode != .Adventure { dealer.pressure = TileDealer.classicPressure(score) }
            let fresh = dealer.deal(board)
            for (k, p) in fresh.enumerated() { tray[k] = p }
            rounds += 1
            dealt = fresh
        }
        return Turn(placement: placement, dealt: dealt, outcome: board.anyFits(tray) ? .Going : .Stuck)
    }

    /** The scene shows goal progress as gems land; this keeps the HUD counters in step. */
    func goalTick(_ goal: Int) {
        if goal >= remaining.count { return }
        remaining[goal] = board.remaining(goal)
        goalBumps[goal] += 1
    }

    private func syncGoals() { for g in remaining.indices { remaining[g] = board.remaining(g) } }

    func notePick() { pickTick += 1 }
    func noteInvalid() { invalidTick += 1 }

    func finishWin() {
        if phase != .Playing { return }
        syncGoals()
        elapsedSeconds = Int((Days.nowMillis() - startedAt) / 1000)
        let par = max(1, level?.par ?? 1)
        stars = rounds <= par ? 3 : (Double(rounds) <= Double(par) * 1.4 ? 2 : 1)
        coinsEarned = 15 + stars * 5 + (level?.id ?? 0) / 25
        TileBank.earn(coinsEarned)
        phase = .Won
    }

    func showNoSpace() {
        if phase != .Playing { return }
        phase = revived ? finishRun() : .NoSpace
    }

    var canRevive: Bool { !revived && TileBank.coins >= TileBank.REVIVE_COST }

    func revive() {
        if phase != .NoSpace || revived || !TileBank.spend(TileBank.REVIVE_COST) { return }
        revived = true
        let cleared = board.revive()
        for (k, p) in dealer.deal(board, rescue: true).enumerated() { tray[k] = p }
        rounds += 1
        phase = .Playing
        scene.animateRevive(cleared, tray)
    }

    func declineRevive() {
        if phase != .NoSpace { return }
        phase = finishRun()
    }

    private func finishRun() -> Phase {
        elapsedSeconds = Int((Days.nowMillis() - startedAt) / 1000)
        switch mode {
        case .Adventure:
            break
        case .Classic:
            if score > TileRecords.classicBest { TileRecords.classicBest = score; isNewBest = true }
            coinsEarned = max(5, score / 200)
        case .Daily:
            if score > TileRecords.dailyBest(day) { TileRecords.setDailyBest(day, score); isNewBest = true }
            coinsEarned = max(5, score / 150) + (reachedTarget ? 20 : 0)
        }
        TileBank.earn(coinsEarned)
        return .Over
    }

    /** A placement the bot likes, for the hint hand. */
    func hint() -> (Int, Int)? {
        guard let m = TileBot.bestMove(board, tray) else { return nil }
        return (m.slot, m.origin)
    }
}
