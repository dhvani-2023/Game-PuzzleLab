import Foundation
import Observation

enum PatchShape: String, CaseIterable, Hashable {
    case Square, Wide, Tall

    var title: String { rawValue }

    static func of(_ height: Int, _ width: Int) -> PatchShape {
        if height == width { return .Square }
        if width > height { return .Wide }
        return .Tall
    }

    static func parse(_ raw: String?) -> PatchShape? {
        switch raw {
        case "square": return .Square
        case "wide": return .Wide
        case "tall": return .Tall
        default: return nil
        }
    }
}

struct Cell: Hashable {
    let row: Int
    let col: Int

    init(_ row: Int, _ col: Int) {
        self.row = row
        self.col = col
    }
}

struct GridRect: Hashable {
    let row: Int
    let col: Int
    let height: Int
    let width: Int

    init(_ row: Int, _ col: Int, _ height: Int, _ width: Int) {
        self.row = row
        self.col = col
        self.height = height
        self.width = width
    }

    var area: Int { height * width }
    var shape: PatchShape { PatchShape.of(height, width) }

    func contains(_ cell: Cell) -> Bool {
        cell.row >= row && cell.row < row + height && cell.col >= col && cell.col < col + width
    }

    func intersects(_ o: GridRect) -> Bool {
        row < o.row + o.height && o.row < row + height && col < o.col + o.width && o.col < col + width
    }

    static func spanning(_ a: Cell, _ b: Cell) -> GridRect {
        GridRect(min(a.row, b.row), min(a.col, b.col), abs(a.row - b.row) + 1, abs(a.col - b.col) + 1)
    }
}

struct PatchesClue: Hashable {
    let r: Int
    let c: Int
    let n: Int?
    let s: PatchShape?
    let k: Int

    init(_ r: Int, _ c: Int, _ n: Int?, _ s: PatchShape?, _ k: Int) {
        self.r = r
        self.c = c
        self.n = n
        self.s = s
        self.k = k
    }

    var cell: Cell { Cell(r, c) }

    func accepts(_ rect: GridRect) -> Bool {
        if let n, rect.area != n { return false }
        if let s, rect.shape != s { return false }
        return true
    }
}

final class PatchesLevel: PackLevel {
    let id: Int
    let tier: DifficultyTier
    let rows: Int
    let cols: Int
    let clues: [PatchesClue]
    /// One rectangle per clue, in clue order.
    let solution: [GridRect]

    init(_ id: Int, _ tier: DifficultyTier, _ rows: Int, _ cols: Int, _ clues: [PatchesClue], _ solution: [GridRect]) {
        self.id = id
        self.tier = tier
        self.rows = rows
        self.cols = cols
        self.clues = clues
        self.solution = solution
    }

    var sizeLabel: String { "\(rows)×\(cols)" }

    static func parse(_ o: JSONObject) -> PatchesLevel {
        let a = o.getJSONArray("clues")
        let clues: [PatchesClue] = (0..<a.length()).map { i in
            let c = a.getJSONObject(i)
            return PatchesClue(c.getInt("r"), c.getInt("c"), c.has("n") ? c.getInt("n") : nil, PatchShape.parse(c.optString("s", "")), c.getInt("k"))
        }
        let s = o.getJSONArray("solution")
        let solution: [GridRect] = (0..<s.length()).map { i in
            let r = s.getJSONArray(i)
            return GridRect(r.getInt(0), r.getInt(1), r.getInt(2), r.getInt(3))
        }
        return PatchesLevel(o.getInt("id"), DifficultyTier.parse(o.getString("tier")), o.getInt("rows"), o.getInt("cols"), clues, solution)
    }
}

/// Rules and state for one Patches board (a 1:1 port of the iOS `PatchesGame`).
@Observable
final class PatchesGame: PuzzleSession {
    enum Feedback: String {
        case NoClue = "Every patch needs exactly one clue"
        case TooManyClues = "A patch can only hold one clue"

        var message: String { rawValue }
    }

    let level: PatchesLevel

    /// Placed patches keyed by clue index.
    private(set) var patches: [Int: GridRect] = [:]
    private(set) var hintsUsed = 0
    private(set) var isSolved = false
    var elapsed = 0

    private(set) var placeCount = 0
    private(set) var errorCount = 0
    private(set) var feedback: Feedback?
    private(set) var revision = 0
    private(set) var lastHintClue: Int?
    /// The last placed or hinted patch's clue, for its sound.
    @ObservationIgnored private(set) var lastPlaced: Int?

    private var history: [[Int: GridRect]] = []
    @ObservationIgnored private let clueAtCell: [Cell: Int]

    init(_ level: PatchesLevel, _ savedState: String?) {
        self.level = level
        var map: [Cell: Int] = [:]
        for (index, clue) in level.clues.enumerated() { map[clue.cell] = index }
        clueAtCell = map
        if let savedState, let o = JSONObject(string: savedState) {
            var saved: [Int: GridRect] = [:]
            if let p = o.optJSONObject("p") {
                for k in p.keys() {
                    guard let index = Int(k) else { continue }
                    let r = p.getJSONArray(k)
                    saved[index] = GridRect(r.getInt(0), r.getInt(1), r.getInt(2), r.getInt(3))
                }
            }
            if validated(saved) {
                patches = saved
                elapsed = o.optInt("e")
                hintsUsed = o.optInt("h")
            }
        }
    }

    /// True if the saved patches still fit this level's grid and clues.
    private func validated(_ saved: [Int: GridRect]) -> Bool {
        var placed: [GridRect] = []
        for (index, rect) in saved {
            if !level.clues.indices.contains(index) || rect.row < 0 || rect.col < 0 || rect.height <= 0 || rect.width <= 0 ||
                rect.row + rect.height > level.rows || rect.col + rect.width > level.cols ||
                cluesIn(rect) != [index] ||
                placed.contains(where: { $0.intersects(rect) }) {
                return false
            }
            placed.append(rect)
        }
        return true
    }

    var rows: Int { level.rows }
    var cols: Int { level.cols }
    var levelID: Int { level.id }
    var canUndo: Bool { !history.isEmpty && !isSolved }
    var canClear: Bool { !patches.isEmpty && !isSolved }
    var coveredCells: Int { patches.values.reduce(0) { $0 + $1.area } }
    var progress: Float { Float(coveredCells) / Float(rows * cols) }
    var progressText: String { "\(coveredCells)/\(rows * cols)" }
    var statusText: String { isSolved ? "Solved!" : "Fill every cell — no gaps, no overlaps" }
    var feedbackMessage: String? { feedback?.message }
    var actionCount: Int { placeCount }

    func clue(_ cell: Cell) -> Int? { clueAtCell[cell] }
    func cluesIn(_ rect: GridRect) -> [Int] { level.clues.indices.filter { rect.contains(level.clues[$0].cell) } }
    func patchOwner(_ cell: Cell) -> Int? { patches.first(where: { $0.value.contains(cell) })?.key }
    func isValid(_ clueIndex: Int) -> Bool { patches[clueIndex].map { level.clues[clueIndex].accepts($0) } ?? false }

    /// Places a dragged rectangle. It replaces the clue's old patch and any patch it overlaps.
    @discardableResult
    func place(_ rect: GridRect) -> Bool {
        if isSolved { return false }
        let inside = cluesIn(rect)
        if inside.count != 1 {
            reject(inside.isEmpty ? .NoClue : .TooManyClues)
            return false
        }
        let clueIndex = inside[0]
        if patches[clueIndex] == rect { return true }
        apply(rect, clueIndex)
        return true
    }

    /// A tap removes the patch under the finger, or drops a 1×1 patch on a size-1 clue. Returns true if a patch was removed.
    @discardableResult
    func tap(_ cell: Cell) -> Bool {
        if isSolved { return false }
        if let owner = patchOwner(cell) {
            pushHistory()
            var next = patches
            next[owner] = nil
            patches = next
            changed()
            return true
        }
        guard let clueIndex = clue(cell) else { return false }
        let single = GridRect(cell.row, cell.col, 1, 1)
        if level.clues[clueIndex].accepts(single) { apply(single, clueIndex) }
        return false
    }

    func undo() {
        if isSolved || history.isEmpty { return }
        patches = history[history.count - 1]
        history = Array(history.dropLast())
        changed()
    }

    func clear() {
        if patches.isEmpty || isSolved { return }
        pushHistory()
        patches = [:]
        changed()
    }

    /// Reveals one patch from the solution: first fixes a wrong patch, then fills a missing one.
    func hint() {
        if isSolved { return }
        let solution = level.solution
        guard let target = solution.indices.first(where: { patches[$0] != nil && patches[$0] != solution[$0] })
            ?? solution.indices.first(where: { patches[$0] == nil }) else { return }
        hintsUsed += 1
        lastHintClue = target
        apply(solution[target], target)
    }

    func clearFeedback() { feedback = nil }

    private func apply(_ rect: GridRect, _ clueIndex: Int) {
        pushHistory()
        var next = patches.filter { $0.key == clueIndex || !$0.value.intersects(rect) }
        next[clueIndex] = rect
        patches = next
        feedback = nil
        lastPlaced = clueIndex
        placeCount += 1
        changed()
    }

    private func reject(_ reason: Feedback) {
        feedback = reason
        errorCount += 1
    }

    private func pushHistory() {
        history = Array((history + [patches]).suffix(200))
    }

    private func changed() {
        revision += 1
        if patches.count == level.clues.count && coveredCells == rows * cols && level.clues.indices.allSatisfy(isValid) { isSolved = true }
    }

    func encodeState() -> String? {
        if isSolved || (patches.isEmpty && elapsed == 0) { return nil }
        var p = JSONObject()
        for (k, r) in patches { p.put(String(k), [r.row, r.col, r.height, r.width]) }
        var o = JSONObject()
        o.put("p", p)
        o.put("e", elapsed)
        o.put("h", hintsUsed)
        return o.toString()
    }
}
