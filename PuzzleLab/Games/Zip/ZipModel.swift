import Foundation
import Observation

final class ZipLevel: PackLevel {
    let id: Int
    let tier: DifficultyTier
    let rows: Int
    let cols: Int
    /// Cell indices (`row * cols + col`) of the numbered dots, in order 1…n.
    let dots: [Int]
    /// Pairs of neighbouring cells the path may not cross between.
    let walls: [(first: Int, second: Int)]
    /// The unique solution: every cell index in path order.
    let solution: [Int]

    init(_ id: Int, _ tier: DifficultyTier, _ rows: Int, _ cols: Int, _ dots: [Int], _ walls: [(first: Int, second: Int)], _ solution: [Int]) {
        self.id = id
        self.tier = tier
        self.rows = rows
        self.cols = cols
        self.dots = dots
        self.walls = walls
        self.solution = solution
    }

    var sizeLabel: String { "\(rows)×\(cols)" }
    var cellCount: Int { rows * cols }

    func row(_ cell: Int) -> Int { cell / cols }
    func col(_ cell: Int) -> Int { cell % cols }
    func cell(_ row: Int, _ col: Int) -> Int? { row >= 0 && row < rows && col >= 0 && col < cols ? row * cols + col : nil }

    static func parse(_ o: JSONObject) -> ZipLevel {
        func ints(_ a: JSONArray) -> [Int] { (0..<a.length()).map { a.getInt($0) } }
        let w = o.getJSONArray("walls")
        let walls: [(first: Int, second: Int)] = (0..<w.length()).map { i in
            let p = w.getJSONArray(i)
            return (p.getInt(0), p.getInt(1))
        }
        return ZipLevel(o.getInt("id"), DifficultyTier.parse(o.getString("tier")), o.getInt("rows"), o.getInt("cols"),
                        ints(o.getJSONArray("dots")), walls, ints(o.getJSONArray("solution")))
    }
}

/// Rules and state for one Zip board: a single path from dot 1 through every cell (iOS `ZipGame`).
@Observable
final class ZipGame: PuzzleSession {
    enum Feedback: String {
        case StartAtOne = "Start your path on 1"
        case WrongOrder = "Connect the dots in order"
        case EndTooSoon = "Fill every cell before the last dot"

        var message: String { rawValue }
    }

    let level: ZipLevel

    private(set) var path: [Int] = []
    private(set) var hintsUsed = 0
    private(set) var isSolved = false
    var elapsed = 0

    /// Bumped when the path reaches a new dot.
    private(set) var dotCount = 0
    private(set) var errorCount = 0
    private(set) var feedback: Feedback?
    private(set) var revision = 0
    /// Path positions revealed by the latest hint, for a highlight.
    private(set) var hintRange: ClosedRange<Int>?

    private var history: [[Int]] = []
    @ObservationIgnored private var strokeStart: [Int]?
    @ObservationIgnored private var strokeHadError = false
    @ObservationIgnored private let dotRank: [Int: Int]
    @ObservationIgnored private let walls: Set<Int>
    /// Path index of each cell, or -1 (Kotlin's `position` map).
    @ObservationIgnored private var position: [Int]

    init(_ level: ZipLevel, _ savedState: String?) {
        self.level = level
        var rank: [Int: Int] = [:]
        for (index, value) in level.dots.enumerated() { rank[value] = index }
        dotRank = rank
        walls = Set(level.walls.map { min($0.first, $0.second) * level.cellCount + max($0.first, $0.second) })
        position = [Int](repeating: -1, count: max(level.cellCount, 0))
        if let savedState, let o = JSONObject(string: savedState) {
            let p: [Int] = o.optJSONArray("p").map { a in (0..<a.length()).map { a.getInt($0) } } ?? []
            if isValid(p) {
                path = p
                elapsed = o.optInt("e")
                hintsUsed = o.optInt("h")
            }
        }
        reindex()
        dotCount = visitedDots
    }

    var cellCount: Int { level.cellCount }
    var end: Int? { path.last }

    func dot(_ cell: Int) -> Int? { dotRank[cell] }
    var visitedDots: Int { path.reduce(0) { $0 + (dotRank[$1] != nil ? 1 : 0) } }
    /// Rank of the dot the path must reach next.
    var nextDot: Int? { visitedDots < level.dots.count ? visitedDots : nil }
    func pathIndex(_ cell: Int) -> Int? {
        guard cell >= 0 && cell < position.count else { return nil }
        let i = position[cell]
        return i >= 0 ? i : nil
    }
    func hasWall(_ a: Int, _ b: Int) -> Bool { walls.contains(min(a, b) * cellCount + max(a, b)) }

    // Gestures

    func beginStroke(_ cell: Int) {
        if isSolved { return }
        strokeStart = path
        strokeHadError = false
        let index = pathIndex(cell)
        let e = end
        if let index {
            truncate(index)
        } else if cell == level.dots.first {
            replacePath([cell])
        } else if let e, isNeighbour(e, cell) {
            step(cell)
        } else if path.isEmpty {
            reject(.StartAtOne)
        }
    }

    func drag(_ cell: Int) {
        if isSolved || strokeStart == nil { return }
        guard let e = end else { return }
        if cell == e { return }
        if let i = pathIndex(cell) { truncate(i); return }
        // Walk toward the finger one cell at a time so fast drags don't skip.
        var current = e
        while current != cell {
            let dr = level.row(cell) - level.row(current)
            let dc = level.col(cell) - level.col(current)
            let horizontal = level.cell(level.row(current), level.col(current) + dc.signum())
            let vertical = level.cell(level.row(current) + dr.signum(), level.col(current))
            let preferred: [Int?] = abs(dc) >= abs(dr)
                ? [dc != 0 ? horizontal : nil, dr != 0 ? vertical : nil]
                : [dr != 0 ? vertical : nil, dc != 0 ? horizontal : nil]
            guard let next = preferred.compactMap({ $0 }).first(where: { canEnter($0) }) else { break }
            if !step(next) { break }
            current = next
        }
    }

    func endStroke() {
        if let start = strokeStart, start != path { history = Array((history + [start]).suffix(200)) }
        strokeStart = nil
    }

    // Tools

    var canUndo: Bool { !history.isEmpty && !isSolved }

    func undo() {
        if isSolved || history.isEmpty { return }
        let previous = history[history.count - 1]
        history = Array(history.dropLast())
        replacePath(previous)
    }

    func clear() {
        if isSolved || path.isEmpty { return }
        history = history + [path]
        replacePath([])
    }

    /// Fixes any wrong part of the path, then draws the solution up to the next dot.
    func hint() {
        if isSolved { return }
        let solution = level.solution
        var correct = 0
        while correct < path.count && path[correct] == solution[correct] { correct += 1 }
        var target = max(correct, 1)
        while target < solution.count - 1 && dotRank[solution[target]] == nil { target += 1 }
        history = history + [path]
        hintsUsed += 1
        hintRange = correct...target
        replacePath(Array(solution[0...target]))
    }

    func clearFeedback() { feedback = nil }

    // Internals

    private func isNeighbour(_ a: Int, _ b: Int) -> Bool {
        let dr = abs(level.row(a) - level.row(b))
        let dc = abs(level.col(a) - level.col(b))
        return dr + dc == 1 && !hasWall(a, b)
    }

    private func canEnter(_ cell: Int) -> Bool {
        guard let e = end else { return false }
        return pathIndex(cell) == nil && isNeighbour(e, cell)
    }

    @discardableResult
    private func step(_ cell: Int) -> Bool {
        if !canEnter(cell) { return false }
        if let e = end, dotRank[e] == level.dots.count - 1 { reject(.EndTooSoon); return false }
        if let rank = dotRank[cell] {
            if rank != visitedDots { reject(.WrongOrder); return false }
            if rank == level.dots.count - 1 && path.count + 1 < cellCount { reject(.EndTooSoon); return false }
        }
        path = path + [cell]
        position[cell] = path.count - 1
        changed()
        return true
    }

    private func truncate(_ index: Int) {
        if index >= path.count - 1 { return }
        replacePath(Array(path[0...index]))
    }

    private func replacePath(_ newPath: [Int]) {
        path = newPath
        reindex()
        changed()
    }

    private func reindex() {
        for i in position.indices { position[i] = -1 }
        for (i, c) in path.enumerated() where c >= 0 && c < position.count { position[c] = i }
    }

    private func reject(_ reason: Feedback) {
        if strokeHadError { return }
        strokeHadError = true
        feedback = reason
        errorCount += 1
    }

    private func changed() {
        revision += 1
        let dots = visitedDots
        if dots > dotCount { feedback = nil }
        dotCount = dots
        if path.count == cellCount && path.last == level.dots.last { isSolved = true }
    }

    private func isValid(_ p: [Int]) -> Bool {
        guard let first = p.first else { return true }
        if first != level.dots.first || Set(p).count != p.count { return false }
        var nextRank = 1
        for i in stride(from: 1, to: p.count, by: 1) {
            let a = p[i - 1]
            let b = p[i]
            if b < 0 || b >= level.cellCount { return false }
            let dr = abs(level.row(a) - level.row(b))
            let dc = abs(level.col(a) - level.col(b))
            if dr + dc != 1 || walls.contains(min(a, b) * level.cellCount + max(a, b)) { return false }
            if let r = dotRank[b] {
                if r != nextRank { return false }
                nextRank += 1
            }
        }
        return true
    }

    var levelID: Int { level.id }
    var canClear: Bool { !path.isEmpty && !isSolved }
    var progress: Float { Float(path.count) / Float(cellCount) }
    var progressText: String { "\(path.count)/\(cellCount)" }
    var statusText: String { isSolved ? "Solved!" : "Connect 1 → \(level.dots.count) through every cell" }
    var feedbackMessage: String? { feedback?.message }
    var actionCount: Int { dotCount }

    func encodeState() -> String? {
        if isSolved || (path.isEmpty && elapsed == 0) { return nil }
        return "{\"p\":[\(path.map(String.init).joined(separator: ","))],\"e\":\(elapsed),\"h\":\(hintsUsed)}"
    }
}
