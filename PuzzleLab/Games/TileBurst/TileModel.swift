import Foundation
import GameKit

/**
 * The board is 8×8. Cell `i` is row `i / 8` (0 = top), column `i % 8`; bit `i` of a UInt64 marks
 * it, so occupancy checks are single AND operations.
 */
enum TileGrid {
    static let SIZE = 8
    static let CELLS = 64

    @inline(__always) static func bit(_ i: Int) -> UInt64 { 1 << UInt64(i) }
    @inline(__always) static func index(_ r: Int, _ c: Int) -> Int { r * SIZE + c }
    @inline(__always) static func row(_ i: Int) -> Int { i / SIZE }
    @inline(__always) static func col(_ i: Int) -> Int { i % SIZE }

    static let rowMasks: [UInt64] = (0..<SIZE).map { UInt64(0xFF) << UInt64($0 * SIZE) }
    static let colMasks: [UInt64] = (0..<SIZE).map { c in (0..<SIZE).reduce(UInt64(0)) { m, r in m | bit(index(r, c)) } }
    static let firstCol = colMasks[0]
    static let lastCol = colMasks[SIZE - 1]
    static let firstRow = rowMasks[0]
    static let lastRow = rowMasks[SIZE - 1]

    static func cells(_ mask: UInt64) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(mask.nonzeroBitCount)
        var m = mask
        while m != 0 {
            out.append(m.trailingZeroBitCount)
            m &= m - 1
        }
        return out
    }

    struct Lines {
        let rows: [Int]
        let cols: [Int]
        let mask: UInt64
        static let none = Lines(rows: [], cols: [], mask: 0)
    }

    /** Full rows and columns in `occupancy`, and the cells they cover. */
    static func lines(_ occupancy: UInt64) -> Lines {
        var rows: [Int] = []
        var cols: [Int] = []
        var mask: UInt64 = 0
        for r in 0..<SIZE where occupancy & rowMasks[r] == rowMasks[r] { rows.append(r); mask |= rowMasks[r] }
        for c in 0..<SIZE where occupancy & colMasks[c] == colMasks[c] { cols.append(c); mask |= colMasks[c] }
        return Lines(rows: rows, cols: cols, mask: mask)
    }

    static func lineMask(_ occupancy: UInt64) -> UInt64 {
        var mask: UInt64 = 0
        for r in 0..<SIZE where occupancy & rowMasks[r] == rowMasks[r] { mask |= rowMasks[r] }
        for c in 0..<SIZE where occupancy & colMasks[c] == colMasks[c] { mask |= colMasks[c] }
        return mask
    }

    /** Number of full rows plus full columns, and their cells (allocation-free `lines`). */
    @inline(__always)
    static func lineCount(_ occupancy: UInt64) -> (count: Int, mask: UInt64) {
        var n = 0
        var mask: UInt64 = 0
        for r in 0..<SIZE where occupancy & rowMasks[r] == rowMasks[r] { n += 1; mask |= rowMasks[r] }
        for c in 0..<SIZE where occupancy & colMasks[c] == colMasks[c] { n += 1; mask |= colMasks[c] }
        return (n, mask)
    }

    /** Empty cells walled in on all four sides (by blocks or the board edge). */
    static func holes(_ occ: UInt64) -> Int {
        let empty = ~occ
        let up = (occ << 8) | firstRow
        let down = (occ >> 8) | lastRow
        let left = ((occ << 1) & ~firstCol) | firstCol
        let right = ((occ >> 1) & ~lastCol) | lastCol
        return (empty & up & down & left & right).nonzeroBitCount
    }

    /** Edges between a filled and an empty cell. */
    static func roughness(_ occ: UInt64) -> Int {
        let horizontal = (occ ^ (occ >> 1)) & ~lastCol
        let vertical = (occ ^ (occ >> 8)) & ~lastRow
        return horizontal.nonzeroBitCount + vertical.nonzeroBitCount
    }
}

/** A piece shape. Cells are normalized so the top-left of its bounding box is (0, 0). */
final class TileShape: Hashable {
    enum Family: Int, CaseIterable { case Single, Line2, Line3, Line4, Line5, Square2, Square3, Rect, SmallL, L4, BigL, Tee, Skew }

    /** One board position: the top-left cell and the cells the shape covers there. */
    struct Placement {
        let origin: Int
        let mask: UInt64
    }

    let id: Int
    let family: Family
    let tone: Int
    /** (row, col) of every cell, in reading order. */
    let cells: [(Int, Int)]
    let rows: Int
    let cols: Int
    /** Every board position the shape can occupy. */
    let placements: [Placement]
    private let early: Double
    private let late: Double

    init(_ id: Int, _ family: Family, _ tone: Int, _ art: [String]) {
        self.id = id
        self.family = family
        self.tone = tone
        var list: [(Int, Int)] = []
        for (r, line) in art.enumerated() {
            for (c, ch) in line.enumerated() where ch == "#" { list.append((r, c)) }
        }
        cells = list
        rows = list.map { $0.0 }.max()! + 1
        cols = list.map { $0.1 }.max()! + 1
        var p: [Placement] = []
        for r0 in 0...(TileGrid.SIZE - rows) {
            for c0 in 0...(TileGrid.SIZE - cols) {
                let mask = list.reduce(UInt64(0)) { m, rc in m | TileGrid.bit(TileGrid.index(r0 + rc.0, c0 + rc.1)) }
                p.append(Placement(origin: TileGrid.index(r0, c0), mask: mask))
            }
        }
        placements = p
        (early, late) = TileShape.weights(family)
    }

    var size: Int { cells.count }

    func mask(_ origin: Int) -> UInt64? {
        let r0 = TileGrid.row(origin)
        let c0 = TileGrid.col(origin)
        if r0 < 0 || c0 < 0 || r0 + rows > TileGrid.SIZE || c0 + cols > TileGrid.SIZE { return nil }
        var m: UInt64 = 0
        for (r, c) in cells { m |= TileGrid.bit(TileGrid.index(r0 + r, c0 + c)) }
        return m
    }

    func fits(_ occupancy: UInt64) -> Bool {
        for p in placements where p.mask & occupancy == 0 { return true }
        return false
    }

    /** Selection weight at pressure 0 (kind) and 1 (mean). */
    private static func weights(_ family: Family) -> (Double, Double) {
        switch family {
        case .Single: return (0.5, 0.25)
        case .Line2: return (1.0, 0.6)
        case .Line3: return (1.0, 0.8)
        case .Line4: return (0.8, 0.8)
        case .Line5: return (0.35, 0.75)
        case .Square2: return (1.2, 0.9)
        case .Square3: return (0.35, 0.9)
        case .Rect: return (0.5, 0.7)
        case .SmallL: return (0.7, 0.6)
        case .L4: return (0.3, 0.35)
        case .BigL: return (0.25, 0.55)
        case .Tee: return (0.45, 0.5)
        case .Skew: return (0.4, 0.5)
        }
    }

    func weight(_ pressure: Double) -> Double {
        early + (late - early) * pressure.coerceIn(0.0, 1.0)
    }

    static func == (a: TileShape, b: TileShape) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /** Every shape in the game, built once. */
    static let all: [TileShape] = {
        let defs: [(Family, Int, [String])] = [
            (.Single, 2, ["#"]),
            (.Line2, 3, ["##"]), (.Line2, 3, ["#", "#"]),
            (.Line3, 1, ["###"]), (.Line3, 1, ["#", "#", "#"]),
            (.Line4, 4, ["####"]), (.Line4, 4, ["#", "#", "#", "#"]),
            (.Line5, 0, ["#####"]), (.Line5, 0, ["#", "#", "#", "#", "#"]),
            (.Square2, 2, ["##", "##"]),
            (.Square3, 3, ["###", "###", "###"]),
            (.Rect, 5, ["###", "###"]), (.Rect, 5, ["##", "##", "##"]),
            (.SmallL, 6, ["##", "#."]), (.SmallL, 6, ["##", ".#"]), (.SmallL, 6, ["#.", "##"]), (.SmallL, 6, [".#", "##"]),
            (.L4, 5, ["#..", "###"]), (.L4, 1, ["..#", "###"]), (.L4, 5, ["###", "#.."]), (.L4, 1, ["###", "..#"]),
            (.L4, 5, ["#.", "#.", "##"]), (.L4, 1, [".#", ".#", "##"]), (.L4, 5, ["##", "#.", "#."]), (.L4, 1, ["##", ".#", ".#"]),
            (.BigL, 0, ["###", "#..", "#.."]), (.BigL, 0, ["###", "..#", "..#"]), (.BigL, 0, ["#..", "#..", "###"]), (.BigL, 0, ["..#", "..#", "###"]),
            (.Tee, 6, ["###", ".#."]), (.Tee, 6, [".#.", "###"]), (.Tee, 6, ["#.", "##", "#."]), (.Tee, 6, [".#", "##", ".#"]),
            (.Skew, 4, ["##.", ".##"]), (.Skew, 4, [".##", "##."]), (.Skew, 4, ["#.", "##", ".#"]), (.Skew, 4, [".#", "##", "#."]),
        ]
        return defs.enumerated().map { i, d in TileShape(i, d.0, d.1, d.2) }
    }()
}

/** Collectibles hidden inside blocks in Adventure. */
enum TileGem: Int, CaseIterable {
    case Star, Ruby, Diamond

    var code: Character {
        switch self {
        case .Star: return "s"
        case .Ruby: return "r"
        case .Diamond: return "d"
        }
    }

    var title: String {
        switch self {
        case .Star: return "Star"
        case .Ruby: return "Ruby"
        case .Diamond: return "Diamond"
        }
    }

    var plural: String {
        switch self {
        case .Star: return "Stars"
        case .Ruby: return "Rubies"
        case .Diamond: return "Diamonds"
        }
    }

    var ordinal: Int { rawValue }

    static func of(_ code: Character) -> TileGem? { allCases.first { $0.code == code } }

    static func parse(_ raw: String?) -> TileGem? {
        switch raw {
        case "star": return .Star
        case "ruby": return .Ruby
        case "diamond": return .Diamond
        default: return nil
        }
    }
}

struct TileGoal: Equatable {
    enum Kind: Int, CaseIterable { case Collect, Score, Clear }

    let kind: Kind
    var gem: TileGem? = nil
    var n: Int? = nil

    init(_ kind: Kind, gem: TileGem? = nil, n: Int? = nil) {
        self.kind = kind
        self.gem = gem
        self.n = n
    }
}

/** A tray piece: a shape, optionally carrying a gem on one of its cells. */
struct TilePiece {
    let id: Int
    let shape: TileShape
    var gemCell: Int? = nil
    var gem: TileGem? = nil
}

/** One Adventure level. `pattern` rows run top to bottom: `.` empty or `0`–`6` a block of that colour. */
final class TileLevel: PackLevel {
    let id: Int
    let tier: DifficultyTier
    let pattern: [String]
    let gems: [String]?
    let goals: [TileGoal]
    /** Tray rounds the bot typically needs; 3 stars at or under par. */
    let par: Int
    let pressure: Double
    let gemRate: Double
    let seed: Int64
    let tip: String?

    init(id: Int, tier: DifficultyTier, pattern: [String], gems: [String]?, goals: [TileGoal], par: Int,
         pressure: Double, gemRate: Double, seed: Int64, tip: String?) {
        self.id = id
        self.tier = tier
        self.pattern = pattern
        self.gems = gems
        self.goals = goals
        self.par = par
        self.pressure = pressure
        self.gemRate = gemRate
        self.seed = seed
        self.tip = tip
    }

    var sizeLabel: String {
        if goals.contains(where: { $0.kind == .Clear }) { return "Clear" }
        if goals.contains(where: { $0.kind == .Collect }) { return "Gems" }
        return "Score"
    }

    /** 0-based world (100 levels each), which picks the theme. */
    var world: Int { (id - 1) / 100 }

    static func parse(_ o: JSONObject) -> TileLevel {
        func strings(_ key: String) -> [String]? {
            o.optJSONArray(key).map { a in (0..<a.length()).map { a.getString($0) } }
        }
        let a = o.getJSONArray("goals")
        let goals: [TileGoal] = (0..<a.length()).map { i in
            let g = a.getJSONObject(i)
            let kind: TileGoal.Kind
            switch g.getString("kind") {
            case "collect": kind = .Collect
            case "clear": kind = .Clear
            default: kind = .Score
            }
            var gem: TileGem? = nil
            if g.has("gem") {
                let k = g.getInt("gem")
                if k >= 0 && k < TileGem.allCases.count { gem = TileGem.allCases[k] }
            }
            return TileGoal(kind, gem: gem, n: g.has("n") ? g.getInt("n") : nil)
        }
        let tip = o.optString("tip", "")
        return TileLevel(
            id: o.getInt("id"), tier: DifficultyTier.parse(o.getString("tier")), pattern: strings("pattern") ?? [], gems: strings("gems"), goals: goals,
            par: o.getInt("par"), pressure: o.optDouble("pressure", 0.0), gemRate: o.optDouble("gemRate", 0.0), seed: o.optLong("seed"),
            tip: tip.isEmpty ? nil : tip
        )
    }

    static func parse(_ o: [String: Any]) -> TileLevel { parse(JSONObject(o)) }
}

/** SplitMix64: tiny, fast and identical everywhere, so a seed always deals the same trays. */
struct TileRNG {
    private var mix: SplitMix64

    init(_ seed: Int64) {
        // Kotlin starts at `seed + golden`; GameKit's SplitMix64 adds the golden ratio before each output.
        mix = SplitMix64(seed: UInt64(bitPattern: seed) &+ 0x9E37_79B9_7F4A_7C15)
    }

    @inline(__always)
    mutating func next() -> UInt64 { mix.nextRaw() }

    @inline(__always)
    mutating func int(_ upper: Int) -> Int {
        upper <= 1 ? 0 : Int(next() % UInt64(upper))
    }

    @inline(__always)
    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }

    mutating func shuffle<T>(_ list: inout [T]) {
        if list.count <= 1 { return }
        var i = list.count - 1
        while i >= 1 {
            let j = int(i + 1)
            list.swapAt(i, j)
            i -= 1
        }
    }
}

struct TileBlock: Equatable {
    let id: Int
    let tone: Int
    var gem: TileGem? = nil
    var prefilled: Bool = false
}

struct TileCleared {
    let cell: Int
    let block: TileBlock
    let distance: Double
}

/** Java's `Math.hypot` for the half-step offsets the board produces (checked against the JVM in the golden test). */
@inline(__always)
func tileHypot(_ a: Double, _ b: Double) -> Double { Foundation.hypot(a, b) }

/** Kotlin `sortedBy { it.distance }`: a stable sort. */
func tileSortedByDistance(_ list: [TileCleared]) -> [TileCleared] {
    list.enumerated().sorted { a, b in
        a.element.distance != b.element.distance ? a.element.distance < b.element.distance : a.offset < b.offset
    }.map(\.element)
}

/** Everything that happened when a piece went down; the scene animates it. */
final class TilePlacement {
    let piece: TilePiece
    var cells: [Int] = []
    var blocks: [TileBlock] = []
    var rows: [Int] = []
    var cols: [Int] = []
    var cleared: [TileCleared] = []
    /** Gems collected, and which goal each counted toward. */
    var gems: [(cell: Int, gem: TileGem, goal: Int?)] = []
    var cellPoints = 0
    var linePoints = 0
    var bonusPoints = 0
    var combo = 0
    var graceLeft = TileBoard.COMBO_GRACE
    var comboBroke = false
    var praise: Int? = nil
    var perfect = false
    var feverStarted = false
    var feverEnded = false

    init(_ piece: TilePiece) { self.piece = piece }

    var lines: Int { rows.count + cols.count }
    var total: Int { cellPoints + linePoints + bonusPoints }
}

/** The block-puzzle rules: place pieces, clear full rows and columns, score, combo and goals. */
final class TileBoard {
    static let COMBO_GRACE = 2
    static let FEVER_COMBO = 8
    static let PERFECT_BONUS = 300
    static let PRAISE_WORDS = ["Nice!", "Sweet!", "Brilliant!", "Dazzling!", "Legendary!"]

    let level: TileLevel?
    private(set) var occupancy: UInt64 = 0
    var blocks: [TileBlock?] = Array(repeating: nil, count: TileGrid.CELLS)
    private(set) var score = 0
    private(set) var combo = 0
    private(set) var misses = 0
    private(set) var bestCombo = 0
    private(set) var placements = 0
    private(set) var linesCleared = 0
    private(set) var collected: [Int]
    private(set) var goalTotals: [Int]
    private var nextID = 1

    var fever: Bool { combo >= TileBoard.FEVER_COMBO }
    var prefilledLeft: Int {
        var n = 0
        for b in blocks where b?.prefilled == true { n += 1 }
        return n
    }

    init(_ level: TileLevel?) {
        self.level = level
        let goals = level?.goals ?? []
        collected = Array(repeating: 0, count: goals.count)
        goalTotals = Array(repeating: 0, count: goals.count)
        if let level { load(level) }
        for (g, goal) in goals.enumerated() {
            goalTotals[g] = goal.kind == .Clear ? prefilledLeft : (goal.n ?? 0)
        }
    }

    private func load(_ level: TileLevel) {
        for r in 0..<TileGrid.SIZE {
            let row: [Character] = r < level.pattern.count ? Array(level.pattern[r]) : []
            var gemRow: [Character] = []
            if let g = level.gems, r < g.count { gemRow = Array(g[r]) }
            for c in 0..<TileGrid.SIZE {
                guard c < row.count, let a = row[c].asciiValue, a >= 48, a <= 57 else { continue }
                let tone = Int(a) - 48
                let i = TileGrid.index(r, c)
                let gem = c < gemRow.count ? TileGem.of(gemRow[c]) : nil
                blocks[i] = TileBlock(id: newID(), tone: tone, gem: gem, prefilled: true)
                occupancy |= TileGrid.bit(i)
            }
        }
        // A starting picture must never already contain a full line.
        let full = TileGrid.lines(occupancy)
        for i in TileGrid.cells(full.mask) where TileGrid.col(i) == TileGrid.SIZE / 2 || TileGrid.row(i) == TileGrid.SIZE / 2 {
            blocks[i] = nil
            occupancy &= ~TileGrid.bit(i)
        }
    }

    private func newID() -> Int {
        let id = nextID
        nextID += 1
        return id
    }

    func canPlace(_ shape: TileShape, _ origin: Int) -> Bool {
        guard let mask = shape.mask(origin) else { return false }
        return mask & occupancy == 0
    }

    func fits(_ shape: TileShape) -> Bool { shape.fits(occupancy) }

    func anyFits(_ pieces: [TilePiece?]) -> Bool {
        for p in pieces { if let p, fits(p.shape) { return true } }
        return false
    }

    /** Rows and columns that placing `shape` at `origin` would complete. */
    func wouldClear(_ shape: TileShape, _ origin: Int) -> TileGrid.Lines {
        guard let mask = shape.mask(origin), mask & occupancy == 0 else { return .none }
        return TileGrid.lines(occupancy | mask)
    }

    func goalIndex(_ kind: TileGoal.Kind, _ gem: TileGem? = nil) -> Int? {
        guard let goals = level?.goals else { return nil }
        return goals.firstIndex { $0.kind == kind && (gem == nil || $0.gem == gem) }
    }

    func remaining(_ goal: Int) -> Int {
        guard let goals = level?.goals, goal >= 0, goal < goals.count else { return 0 }
        let g = goals[goal]
        switch g.kind {
        case .Collect: return max(0, goalTotals[goal] - collected[goal])
        case .Score: return max(0, (g.n ?? 0) - score)
        case .Clear: return prefilledLeft
        }
    }

    var goalsDone: Bool {
        guard let l = level, !l.goals.isEmpty else { return false }
        for g in l.goals.indices where remaining(g) != 0 { return false }
        return true
    }

    /** Gem kinds that collect goals still need. */
    var neededGems: [TileGem] {
        guard let l = level else { return [] }
        var out: [TileGem] = []
        for g in l.goals.indices where l.goals[g].kind == .Collect && remaining(g) > 0 {
            if let gem = l.goals[g].gem { out.append(gem) }
        }
        return out
    }

    /** Puts `piece` with its top-left at `origin`. Returns nil if it doesn't fit. */
    func place(_ piece: TilePiece, _ origin: Int) -> TilePlacement? {
        guard let mask = piece.shape.mask(origin), mask & occupancy == 0 else { return nil }
        let r0 = TileGrid.row(origin)
        let c0 = TileGrid.col(origin)
        let result = TilePlacement(piece)
        for (k, rc) in piece.shape.cells.enumerated() {
            let i = TileGrid.index(r0 + rc.0, c0 + rc.1)
            let block = TileBlock(id: newID(), tone: piece.shape.tone, gem: piece.gemCell == k ? piece.gem : nil)
            blocks[i] = block
            result.cells.append(i)
            result.blocks.append(block)
        }
        occupancy |= mask
        placements += 1
        result.cellPoints = piece.shape.size

        let lines = TileGrid.lines(occupancy)
        result.rows = lines.rows
        result.cols = lines.cols
        let wasFever = fever
        if lines.mask != 0 {
            combo += 1
            misses = 0
            bestCombo = max(bestCombo, combo)
            let n = lines.rows.count + lines.cols.count
            linesCleared += n
            let base = 10 * n * (n + 1)
            var points = Double(base) * (1 + Double(combo - 1) / 4.0)
            if combo >= TileBoard.FEVER_COMBO { points *= 2 }
            result.linePoints = Int(Kt.roundToLong(points))

            let cr = Double(r0) + Double(piece.shape.rows - 1) / 2.0
            let cc = Double(c0) + Double(piece.shape.cols - 1) / 2.0
            for i in TileGrid.cells(lines.mask) {
                guard let block = blocks[i] else { continue }
                let d = tileHypot(Double(TileGrid.row(i)) - cr, Double(TileGrid.col(i)) - cc)
                result.cleared.append(TileCleared(cell: i, block: block, distance: d))
                if let gem = block.gem { result.gems.append((i, gem, collect(gem))) }
                blocks[i] = nil
            }
            result.cleared = tileSortedByDistance(result.cleared)
            occupancy &= ~lines.mask
            if occupancy == 0 {
                result.perfect = true
                result.bonusPoints = TileBoard.PERFECT_BONUS
            }
        } else {
            misses += 1
            if misses > TileBoard.COMBO_GRACE && combo > 0 {
                result.comboBroke = true
                combo = 0
                misses = 0
            }
        }
        result.combo = combo
        result.graceLeft = max(0, TileBoard.COMBO_GRACE - misses)
        result.feverStarted = !wasFever && fever
        result.feverEnded = wasFever && !fever
        result.praise = TileBoard.praise(result.lines, combo)
        score += result.total
        return result
    }

    private func collect(_ gem: TileGem) -> Int? {
        guard let g = goalIndex(.Collect, gem) else { return nil }
        if collected[g] >= goalTotals[g] { return nil }
        collected[g] += 1
        return g
    }

    /** Clears the most crowded 3×3 area (the continue offer after game over). */
    func revive() -> [TileCleared] {
        var best = 0
        var bestCount = -1
        for r in 0...(TileGrid.SIZE - 3) {
            for c in 0...(TileGrid.SIZE - 3) {
                var count = 0
                for dr in 0..<3 { for dc in 0..<3 where blocks[TileGrid.index(r + dr, c + dc)] != nil { count += 1 } }
                if count > bestCount { bestCount = count; best = TileGrid.index(r, c) }
            }
        }
        var cleared: [TileCleared] = []
        let r0 = TileGrid.row(best)
        let c0 = TileGrid.col(best)
        for dr in 0..<3 {
            for dc in 0..<3 {
                let i = TileGrid.index(r0 + dr, c0 + dc)
                guard let block = blocks[i] else { continue }
                cleared.append(TileCleared(cell: i, block: block, distance: tileHypot(Double(dr - 1), Double(dc - 1))))
                blocks[i] = nil
                occupancy &= ~TileGrid.bit(i)
            }
        }
        return tileSortedByDistance(cleared)
    }

    static func praise(_ lines: Int, _ combo: Int) -> Int? {
        if lines <= 0 { return nil }
        let byLines = lines >= 4 ? 3 : lines - 2
        let byCombo: Int
        if combo >= 16 { byCombo = 4 } else if combo >= 11 { byCombo = 3 } else if combo >= 7 { byCombo = 2 } else if combo >= 4 { byCombo = 1 } else if combo >= 2 { byCombo = 0 } else { byCombo = -1 }
        let level = max(byLines, byCombo)
        return level >= 0 ? level : nil
    }
}

/** Deals trays of three pieces: weighted by `pressure`, and fair. */
final class TileDealer {
    private var rng: TileRNG
    private var nextID = 1
    var pressure: Double
    private let gemRate: Double

    init(_ seed: Int64, _ pressure: Double, _ gemRate: Double = 0) {
        rng = TileRNG(seed)
        self.pressure = pressure
        self.gemRate = gemRate
    }

    private var kindness: Double { 0.95 - 0.4 * pressure.coerceIn(0.0, 1.0) }

    func deal(_ board: TileBoard, rescue: Bool = false) -> [TilePiece] {
        deal(board.occupancy, board.neededGems, rescue: rescue)
    }

    func deal(_ occupancy: UInt64, _ neededGems: [TileGem] = [], rescue: Bool = false) -> [TilePiece] {
        let wantSolvable: Bool
        if rescue { wantSolvable = true } else { wantSolvable = rng.unit() < kindness }
        let crowded = Double(occupancy.nonzeroBitCount) / 64.0 > 0.6
        var best: [TileShape]? = nil
        for attempt in 0..<48 {
            var shapes = drawThree((crowded || rescue) && attempt < 40 ? occupancy : nil, attempt > 24)
            if rescue && attempt > 30 {
                for k in shapes.indices where shapes[k].size > 3 { shapes[k] = TileShape.all[1 + rng.int(2)] }
            }
            if !shapes.contains(where: { $0.fits(occupancy) }) { continue }
            if best == nil { best = shapes }
            if !wantSolvable { best = shapes; break }
            var budget = 4000
            if TileDealer.solvable(occupancy, shapes, &budget) { best = shapes; break }
        }
        var shapes = best ?? drawThree(nil, true)
        if best == nil {
            var biggest: TileShape? = nil
            for s in TileShape.all where s.fits(occupancy) { if biggest == nil || s.size > biggest!.size { biggest = s } }
            if let biggest { shapes[0] = biggest }
        }
        var out: [TilePiece] = []
        for s in shapes { out.append(makePiece(s, neededGems)) }
        return out
    }

    private func makePiece(_ shape: TileShape, _ neededGems: [TileGem]) -> TilePiece {
        let id = nextID
        nextID += 1
        if !neededGems.isEmpty && rng.unit() < gemRate {
            let gem = neededGems[rng.int(neededGems.count)]
            return TilePiece(id: id, shape: shape, gemCell: rng.int(shape.size), gem: gem)
        }
        return TilePiece(id: id, shape: shape)
    }

    private func drawThree(_ bias: UInt64?, _ smallerAfter: Bool) -> [TileShape] {
        var out: [TileShape] = []
        if let bias {
            let helpers = TileShape.all.filter { shape in
                shape.placements.contains { $0.mask & bias == 0 && TileGrid.lineMask(bias | $0.mask) != 0 }
            }
            if !helpers.isEmpty && rng.unit() < 0.85 { out.append(pick(helpers)) }
        }
        while out.count < 3 {
            var pool = TileShape.all.filter { s in s.family == .Single || !out.contains(s) }
            if smallerAfter { pool = pool.filter { $0.size <= 4 } }
            out.append(pick(pool))
        }
        rng.shuffle(&out)
        return out
    }

    private func pick(_ pool: [TileShape]) -> TileShape {
        var total = 0.0
        for s in pool { total += s.weight(pressure) }
        var x = rng.unit() * total
        for shape in pool {
            x -= shape.weight(pressure)
            if x <= 0 { return shape }
        }
        return pool[pool.count - 1]
    }

    /** Classic gets meaner as the score climbs. */
    static func classicPressure(_ score: Int) -> Double { min(0.9, Double(score) / 9000.0) }

    /** Can all `shapes` be placed, in some order, with lines clearing between them? */
    static func solvable(_ occ: UInt64, _ shapes: [TileShape], _ budget: inout Int) -> Bool {
        solvable(occ, shapes, 0, &budget)
    }

    /// `used` marks shapes already placed; the rest keep their order, as Kotlin's `rest` list does.
    private static func solvable(_ occ: UInt64, _ shapes: [TileShape], _ used: Int, _ budget: inout Int) -> Bool {
        let n = shapes.count
        if used == (1 << n) - 1 { return true }
        for k in 0..<n where used & (1 << k) == 0 {
            let shape = shapes[k]
            var tried = false
            for j in 0..<k where used & (1 << j) == 0 && shapes[j].id == shape.id { tried = true; break }
            if tried { continue }
            for p in shape.placements {
                if p.mask & occ != 0 { continue }
                budget -= 1
                if budget <= 0 { return true }
                var next = occ | p.mask
                next &= ~TileGrid.lineMask(next)
                if solvable(next, shapes, used | (1 << k), &budget) { return true }
            }
        }
        return false
    }
}

/** Picks placements by looking one move ahead. Used for hints. */
enum TileBot {
    struct Move {
        let slot: Int
        let origin: Int
        let value: Double
    }

    private static let square3 = TileShape.all.first { $0.family == .Square3 }!
    private static let line5 = TileShape.all.filter { $0.family == .Line5 }

    static func bestMove(_ board: TileBoard, _ tray: [TilePiece?]) -> Move? {
        let needed = board.neededGems
        var gemMask: UInt64 = 0
        var pre: UInt64 = 0
        for i in 0..<TileGrid.CELLS {
            guard let b = board.blocks[i] else { continue }
            if let g = b.gem, needed.contains(g) { gemMask |= TileGrid.bit(i) }
            if b.prefilled { pre |= TileGrid.bit(i) }
        }
        let wantsGems = !needed.isEmpty
        let wantsClear = board.goalIndex(.Clear) != nil
        let occupancy = board.occupancy
        let combo = board.combo
        var best: Move? = nil
        for (slot, piece) in tray.enumerated() {
            guard let piece else { continue }
            var others: [TileShape] = []
            for (k, p) in tray.enumerated() where k != slot { if let p { others.append(p.shape) } }
            for p in piece.shape.placements {
                if p.mask & occupancy != 0 { continue }
                var occ = occupancy | p.mask
                let lines = TileGrid.lineCount(occ)
                occ &= ~lines.mask
                let n = Double(lines.count)
                var v = 0.0
                if n > 0 { v += 26 * n + 9 * n * n + Double(min(combo, 10) * 4) } else if combo > 0 { v -= 6 }
                if wantsGems {
                    v += Double(22 * (lines.mask & gemMask).nonzeroBitCount)
                    if piece.gem != nil && p.mask & lines.mask != 0 { v += 22 }
                }
                if wantsClear { v += Double(7 * (lines.mask & pre).nonzeroBitCount) }
                if occ == 0 { v += 120 }
                v -= Double(9 * TileGrid.holes(occ))
                v -= 0.9 * Double(TileGrid.roughness(occ))
                v -= 0.4 * Double(occ.nonzeroBitCount)
                if square3.fits(occ) { v += 10 }
                if line5[0].fits(occ) { v += 4 }
                if line5[1].fits(occ) { v += 4 }
                for shape in others where !shape.fits(occ) { v -= 400 }
                if best == nil || v > best!.value { best = Move(slot: slot, origin: p.origin, value: v) }
            }
        }
        return best
    }
}
