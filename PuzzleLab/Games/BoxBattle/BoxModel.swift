import Foundation
import GameKit

/// The two players in a Box Battle: You (yellow) and the Rival bot (violet).
enum Player: String, CaseIterable, Hashable {
    case You, Rival
}

/// One drawable line between two adjacent dots. Horizontal edges live on the dot-grid rows.
/// (Kotlin `Edge`; renamed so it does not shadow SwiftUI `Edge` for the rest of the app.)
struct BoxEdge: Hashable {
    let horizontal: Bool
    let r: Int
    let c: Int

    init(_ horizontal: Bool, _ r: Int, _ c: Int) {
        self.horizontal = horizontal
        self.r = r
        self.c = c
    }
}

/// A box position (row, column) — Kotlin `Pair<Int, Int>`.
struct BoxCell: Hashable {
    let r: Int
    let c: Int

    init(_ r: Int, _ c: Int) {
        self.r = r
        self.c = c
    }
}

/// A Dots & Boxes board of `rows`×`cols` boxes. Players draw edges; closing the 4th side of a box
/// claims it and earns another turn. The model is mutable and driven by the session.
///
/// Horizontal edges: `hDrawn[r][c]`, r in 0...rows (dot rows), c in 0..<cols.
/// Vertical edges:   `vDrawn[r][c]`, r in 0..<rows, c in 0...cols.
final class BoxModel {
    let rows: Int
    let cols: Int
    private var hDrawn: [[Bool]]
    private var vDrawn: [[Bool]]
    private(set) var hOwner: [[Player?]]
    private(set) var vOwner: [[Player?]]
    private(set) var owner: [[Player?]]

    private(set) var scoreYou = 0
    private(set) var scoreRival = 0

    let totalBoxes: Int

    init(_ rows: Int, _ cols: Int) {
        self.rows = rows
        self.cols = cols
        hDrawn = Array(repeating: Array(repeating: false, count: cols), count: rows + 1)
        vDrawn = Array(repeating: Array(repeating: false, count: cols + 1), count: rows)
        hOwner = Array(repeating: Array(repeating: nil, count: cols), count: rows + 1)
        vOwner = Array(repeating: Array(repeating: nil, count: cols + 1), count: rows)
        owner = Array(repeating: Array(repeating: nil, count: cols), count: rows)
        totalBoxes = rows * cols
    }

    func isDrawn(_ e: BoxEdge) -> Bool { e.horizontal ? hDrawn[e.r][e.c] : vDrawn[e.r][e.c] }

    func ownerOf(_ e: BoxEdge) -> Player? { e.horizontal ? hOwner[e.r][e.c] : vOwner[e.r][e.c] }

    /// Every line not yet drawn.
    func legalEdges() -> [BoxEdge] {
        var out: [BoxEdge] = []
        out.reserveCapacity((rows + 1) * cols + rows * (cols + 1))
        for r in 0...rows { for c in 0..<cols where !hDrawn[r][c] { out.append(BoxEdge(true, r, c)) } }
        for r in 0..<rows { for c in 0...cols where !vDrawn[r][c] { out.append(BoxEdge(false, r, c)) } }
        return out
    }

    var isComplete: Bool { scoreYou + scoreRival >= totalBoxes }

    var winner: Player? {
        if scoreYou > scoreRival { return .You }
        if scoreRival > scoreYou { return .Rival }
        return nil
    }

    func score(_ p: Player) -> Int { p == .You ? scoreYou : scoreRival }

    /// Drawn-side count of box (r,c).
    func sides(_ r: Int, _ c: Int) -> Int {
        var n = 0
        if hDrawn[r][c] { n += 1 }
        if hDrawn[r + 1][c] { n += 1 }
        if vDrawn[r][c] { n += 1 }
        if vDrawn[r][c + 1] { n += 1 }
        return n
    }

    /// The 1 or 2 boxes an edge borders.
    func boxesOf(_ e: BoxEdge) -> [BoxCell] {
        var out: [BoxCell] = []
        out.reserveCapacity(2)
        if e.horizontal {
            if e.r > 0 { out.append(BoxCell(e.r - 1, e.c)) }
            if e.r < rows { out.append(BoxCell(e.r, e.c)) }
        } else {
            if e.c > 0 { out.append(BoxCell(e.r, e.c - 1)) }
            if e.c < cols { out.append(BoxCell(e.r, e.c)) }
        }
        return out
    }

    /// How many boxes drawing `e` would close right now (0, 1 or 2).
    func boxesClosedBy(_ e: BoxEdge) -> Int {
        // `boxesOf(e).count { sides == 3 }`, without the array (the bot calls this thousands of times a move).
        var n = 0
        if e.horizontal {
            if e.r > 0 && sides(e.r - 1, e.c) == 3 { n += 1 }
            if e.r < rows && sides(e.r, e.c) == 3 { n += 1 }
        } else {
            if e.c > 0 && sides(e.r, e.c - 1) == 3 { n += 1 }
            if e.c < cols && sides(e.r, e.c) == 3 { n += 1 }
        }
        return n
    }

    /// True if drawing `e` would hand the opponent a free box (makes some box 3-sided).
    func createsThreeSided(_ e: BoxEdge) -> Bool {
        if e.horizontal {
            return (e.r > 0 && sides(e.r - 1, e.c) == 2) || (e.r < rows && sides(e.r, e.c) == 2)
        }
        return (e.c > 0 && sides(e.r, e.c - 1) == 2) || (e.c < cols && sides(e.r, e.c) == 2)
    }

    /// Draws `e` for `player`, claims any box it closes, and returns the number closed.
    /// The caller keeps the turn when the result is > 0 (combo), otherwise passes it.
    @discardableResult
    func draw(_ e: BoxEdge, _ player: Player) -> Int {
        if isDrawn(e) { return 0 }
        if e.horizontal { hDrawn[e.r][e.c] = true; hOwner[e.r][e.c] = player }
        else { vDrawn[e.r][e.c] = true; vOwner[e.r][e.c] = player }
        var closed = 0
        for b in boxesOf(e) where owner[b.r][b.c] == nil && sides(b.r, b.c) == 4 {
            owner[b.r][b.c] = player
            if player == .You { scoreYou += 1 } else { scoreRival += 1 }
            closed += 1
        }
        return closed
    }

    /// A copy for look-ahead (arrays are shared copy-on-write; the line owners are not needed there).
    private init(copying o: BoxModel) {
        rows = o.rows
        cols = o.cols
        hDrawn = o.hDrawn
        vDrawn = o.vDrawn
        hOwner = o.hOwner
        vOwner = o.vOwner
        owner = o.owner
        scoreYou = o.scoreYou
        scoreRival = o.scoreRival
        totalBoxes = o.totalBoxes
    }

    private func copy() -> BoxModel { BoxModel(copying: self) }

    /// Non-capturing, non-gifting moves (the "safe" set).
    func safeEdges(_ legal: [BoxEdge]? = nil) -> [BoxEdge] {
        (legal ?? legalEdges()).filter { boxesClosedBy($0) == 0 && !createsThreeSided($0) }
    }

    /// Safe moves remaining after playing `e` — used for parity play.
    func safeCountAfter(_ e: BoxEdge) -> Int {
        let m = copy()
        m.draw(e, .Rival)
        return m.safeEdges().count
    }

    /// Rough size of the chain the opponent could run if forced to open with `e`.
    func chainSizeOpenedBy(_ e: BoxEdge) -> Int {
        let m = copy()
        m.draw(e, .Rival)
        let seeds = boxesOf(e).filter { m.sides($0.r, $0.c) == 3 }
        if seeds.isEmpty { return 0 }
        var seen = Set<Int>()
        var stack: [BoxCell] = seeds
        var n = 0
        while let b = stack.popLast() {
            let r = b.r, c = b.c
            let key = r * cols + c
            if !seen.insert(key).inserted { continue }
            if m.owner[r][c] != nil { continue }
            if m.sides(r, c) < 2 { continue }
            n += 1
            // Walk to neighbours across still-open shared edges.
            if r > 0 && !m.hDrawn[r][c] { stack.append(BoxCell(r - 1, c)) }
            if r < rows - 1 && !m.hDrawn[r + 1][c] { stack.append(BoxCell(r + 1, c)) }
            if c > 0 && !m.vDrawn[r][c] { stack.append(BoxCell(r, c - 1)) }
            if c < cols - 1 && !m.vDrawn[r][c + 1] { stack.append(BoxCell(r, c + 1)) }
        }
        return n
    }
}

/// The Rival's move chooser. Difficulty -1 is a rookie for the first levels; 0–3 escalate: take
/// free boxes, avoid gifting, give away the smallest chain when forced, then parity play.
enum BoxBot {
    /// Kotlin's default `Random` (unseeded): a Kotlin XorWow generator seeded from the clock.
    static let defaultRandom = KotlinRandom(Int64(Date().timeIntervalSince1970 * 1000) ^ Int64(UInt32.random(in: 0...UInt32.max)))

    static func move(_ m: BoxModel, _ difficulty: Int, _ rng: KotlinRandom = BoxBot.defaultRandom) -> BoxEdge {
        let legal = m.legalEdges()
        let captures = legal.filter { m.boxesClosedBy($0) > 0 }
        if difficulty < 0 { return gentle(m, legal, captures, difficulty, rng) }
        if !captures.isEmpty {
            // Always grab a free box; take the one that closes the most.
            return maxBy(captures) { m.boxesClosedBy($0) } ?? captures[0]
        }
        if difficulty <= 0 { return legal.kotlinRandom(rng) }

        let safe = m.safeEdges(legal)
        if !safe.isEmpty {
            if difficulty >= 3 {
                // Parity: leave the opponent to run out of safe moves first.
                return minBy(safe) { m.safeCountAfter($0) } ?? safe.kotlinRandom(rng)
            }
            return safe.kotlinRandom(rng)
        }
        // Forced to open a chain: hand over the smallest one (difficulty 2+), else any.
        if difficulty >= 2 { return minBy(legal) { m.chainSizeOpenedBy($0) } ?? legal.kotlinRandom(rng) }
        return legal.kotlinRandom(rng)
    }

    /// Friendly opponents for new players: -1 Rookie, -2 Learner, -3 Improver. Each lets some free
    /// boxes slide and sometimes draws the third side of a box, handing the player a capture;
    /// the chances shrink as the player progresses. (Tuned by simulation: a casual player wins
    /// about 97% vs Rookie, 90% vs Learner, 59% vs Improver.)
    private static func gentle(_ m: BoxModel, _ legal: [BoxEdge], _ captures: [BoxEdge], _ difficulty: Int, _ rng: KotlinRandom) -> BoxEdge {
        let takeChance: Float
        let giftChance: Float
        switch difficulty {
        case -1: takeChance = 0.25; giftChance = 0.6
        case -2: takeChance = 0.5; giftChance = 0.35
        default: takeChance = 0.8; giftChance = 0.15
        }
        if !captures.isEmpty && rng.nextFloat() < takeChance { return captures.kotlinRandom(rng) }
        var quiet = legal.filter { m.boxesClosedBy($0) == 0 }
        if quiet.isEmpty { quiet = legal }
        let gifts = quiet.filter { m.createsThreeSided($0) }
        if !gifts.isEmpty && rng.nextFloat() < giftChance { return gifts.kotlinRandom(rng) }
        return quiet.kotlinRandom(rng)
    }

    /// Kotlin `maxByOrNull`: the first element with the largest key wins ties.
    private static func maxBy(_ items: [BoxEdge], _ key: (BoxEdge) -> Int) -> BoxEdge? {
        var best: BoxEdge?
        var bestKey = Int.min
        for e in items {
            let k = key(e)
            if best == nil || k > bestKey { best = e; bestKey = k }
        }
        return best
    }

    /// Kotlin `minByOrNull`: the first element with the smallest key wins ties.
    private static func minBy(_ items: [BoxEdge], _ key: (BoxEdge) -> Int) -> BoxEdge? {
        var best: BoxEdge?
        var bestKey = Int.max
        for e in items {
            let k = key(e)
            if best == nil || k < bestKey { best = e; bestKey = k }
        }
        return best
    }
}
