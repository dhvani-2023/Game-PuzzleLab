import Foundation
import Observation

/// Coins for Box Battle, earned by winning. Stored on the device only.
enum BoxBank {
    private static let KEY = "progress.boxbattle.coins"

    private(set) static var coins = -1

    static func load() { if coins < 0 { coins = Prefs.sp.contains(KEY) ? Prefs.int(KEY) : 200 } }

    static func earn(_ amount: Int) {
        load()
        if amount <= 0 { return }
        coins += amount
        Prefs.putInt(KEY, coins)
    }
}

/// One game of Box Battle on a level's grid: owns the board, whose turn it is, and the outcome.
@Observable
final class BoxBattleSession {
    enum Phase { case Playing, Won, Lost }

    let level: BoxLevel
    let model: BoxModel
    private let difficulty: Int

    private(set) var turn: Player = .You
    private(set) var phase: Phase = .Playing
    private(set) var revision = 0
    private(set) var scoreYou = 0
    private(set) var scoreRival = 0

    // Last move, for the line "pop" animation and combo feedback.
    private(set) var lastEdge: BoxEdge?
    private(set) var lastOwner: Player = .You
    private(set) var lastEdgeTick = 0
    /// Bumped when a move closes >= 1 box.
    private(set) var claimTick = 0
    private(set) var lastClaimed = 0

    private(set) var stars = 0
    private(set) var coinsEarned = 0

    private let startedAt = Int64(Date().timeIntervalSince1970 * 1000)
    /// How long the game took, set when the board fills.
    @ObservationIgnored private(set) var elapsedSeconds = 0

    init(_ level: BoxLevel) {
        self.level = level
        model = BoxModel(level.rows, level.cols)
        difficulty = level.bot
        BoxBank.load()
    }

    var botThinking: Bool { phase == .Playing && turn == .Rival }

    /// Boxes the move claims (those already on three sides), then the move itself.
    private func commit(_ e: BoxEdge, _ player: Player) -> [BoxCell] {
        let claimed = model.boxesOf(e).filter { model.owner[$0.r][$0.c] == nil && model.sides($0.r, $0.c) == 3 }
        let closed = model.draw(e, player)
        lastEdge = e; lastOwner = player; lastEdgeTick += 1
        scoreYou = model.scoreYou; scoreRival = model.scoreRival
        lastClaimed = closed
        if closed > 0 { claimTick += 1 }
        revision += 1
        if model.isComplete {
            finish()
        } else if closed == 0 {
            turn = player == .You ? .Rival : .You
        }
        // else: same player keeps the turn (combo).
        return claimed
    }

    var canPlayerMove: Bool { phase == .Playing && turn == .You }

    /// The player draws an edge. Returns the boxes it claimed, or nil if the move isn't allowed.
    func playerDraw(_ e: BoxEdge) -> [BoxCell]? {
        if !canPlayerMove || model.isDrawn(e) { return nil }
        return commit(e, .You)
    }

    /// The Rival's next line, chosen before its pencil draws it.
    func chooseBotEdge() -> BoxEdge? { botThinking ? BoxBot.move(model, difficulty) : nil }

    /// Commits the Rival's line once its pencil has finished; returns the boxes it claimed.
    func commitBot(_ e: BoxEdge) -> [BoxCell] {
        if !botThinking || model.isDrawn(e) { return [] }
        return commit(e, .Rival)
    }

    private func finish() {
        elapsedSeconds = Int((Int64(Date().timeIntervalSince1970 * 1000) - startedAt) / 1000)
        let you = model.scoreYou
        let rival = model.scoreRival
        // On the rookie levels a draw still clears the level, so new players keep moving.
        let friendlyDraw = you == rival && level.bot == -1
        if you > rival || friendlyDraw {
            phase = .Won
            if rival == 0 {
                stars = 3
            } else if you - rival >= 2 {
                stars = 2
            } else {
                stars = 1
            }
            coinsEarned = 12 + stars * 6 + level.id / 40
            BoxBank.earn(coinsEarned)
        } else {
            phase = .Lost
        }
    }
}
