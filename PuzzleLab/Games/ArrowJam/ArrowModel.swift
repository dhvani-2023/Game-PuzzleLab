import Foundation

/// Where an arrow points (0 up, 1 down, 2 left, 3 right, as in the level archive).
enum Heading: CaseIterable {
    case Up, Down, Left, Right

    var dr: Int {
        switch self {
        case .Up: return -1
        case .Down: return 1
        case .Left, .Right: return 0
        }
    }

    var dc: Int {
        switch self {
        case .Left: return -1
        case .Right: return 1
        case .Up, .Down: return 0
        }
    }

    var letter: Character {
        switch self {
        case .Up: return "U"
        case .Down: return "D"
        case .Left: return "L"
        case .Right: return "R"
        }
    }

    static var entries: [Heading] { allCases }

    static func between(_ a: ArrowCell, _ b: ArrowCell) -> Heading? {
        if b.r - a.r == -1 && b.c == a.c { return .Up }
        if b.r - a.r == 1 && b.c == a.c { return .Down }
        if b.c - a.c == -1 && b.r == a.r { return .Left }
        if b.c - a.c == 1 && b.r == a.r { return .Right }
        return nil
    }

    static func of(_ letter: Character) -> Heading? { entries.first { $0.letter == letter } }

    /// `of` for a raw ASCII byte of a level code.
    static func of(byte: UInt8) -> Heading? {
        switch byte {
        case 0x55: return .Up     // U
        case 0x44: return .Down   // D
        case 0x4C: return .Left   // L
        case 0x52: return .Right  // R
        default: return nil
        }
    }
}

struct ArrowCell: Hashable {
    let r: Int
    let c: Int

    init(_ r: Int, _ c: Int) {
        self.r = r
        self.c = c
    }

    func step(_ h: Heading, _ count: Int = 1) -> ArrowCell { ArrowCell(r + h.dr * count, c + h.dc * count) }
}

/// One arrow: a snake-shaped body from tail to head. It leaves along its heading.
final class ArrowPiece {
    let id: Int
    let cells: [ArrowCell]
    let heading: Heading
    /// The direction the tail extends backwards in (used for the fly-in).
    let tailHeading: Heading

    var head: ArrowCell { cells[cells.count - 1] }
    var tail: ArrowCell { cells[0] }

    init(_ id: Int, _ cells: [ArrowCell]) {
        self.id = id
        self.cells = cells
        heading = cells.count >= 2 ? (Heading.between(cells[cells.count - 2], cells[cells.count - 1]) ?? .Up) : .Up
        tailHeading = cells.count >= 2 ? (Heading.between(cells[1], cells[0]) ?? .Down) : .Down
    }

    /// Parses `"tailRow.tailCol.moves"`, e.g. `"3.7.RRDDLU"`.
    static func parse(_ id: Int, _ code: String) -> ArrowPiece? {
        if let piece = code.utf8.withContiguousStorageIfAvailable({ parse(id, $0) }) { return piece }
        return Array(code.utf8).withUnsafeBufferPointer { parse(id, $0) }
    }

    /// `parse` straight from the code's UTF-8 bytes (no String allocation).
    static func parse(_ id: Int, _ bytes: UnsafeBufferPointer<UInt8>) -> ArrowPiece? {
        // Kotlin: code.split('.', limit = 3); parts[0] and parts[1] are Ints, parts[2] the moves.
        var dots: [Int] = []
        for (i, b) in bytes.enumerated() where b == 0x2E {
            dots.append(i)
            if dots.count == 2 { break }
        }
        guard dots.count == 2,
              let row = parseInt(bytes, 0, dots[0]),
              let col = parseInt(bytes, dots[0] + 1, dots[1]) else { return nil }
        var cell = ArrowCell(row, col)
        var cells: [ArrowCell] = []
        cells.reserveCapacity(bytes.count - dots[1])
        cells.append(cell)
        var i = dots[1] + 1
        while i < bytes.count {
            guard let h = Heading.of(byte: bytes[i]) else { return nil }
            cell = cell.step(h)
            cells.append(cell)
            i += 1
        }
        return ArrowPiece(id, cells)
    }

    /// Kotlin `String.toIntOrNull()` on `bytes[from..<to]`.
    private static func parseInt(_ bytes: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Int? {
        guard to > from else { return nil }
        var i = from
        var negative = false
        if bytes[i] == 0x2D || bytes[i] == 0x2B {
            negative = bytes[i] == 0x2D
            i += 1
            if i == to { return nil }
        }
        var v = 0
        while i < to {
            let d = Int(bytes[i]) - 48
            guard d >= 0 && d <= 9 else { return nil }
            v = v * 10 + d
            if v > Int(Int32.max) + 1 { return nil }
            i += 1
        }
        if negative { v = -v }
        guard v >= Int(Int32.min) && v <= Int(Int32.max) else { return nil }
        return v
    }

    static func of(_ id: Int, _ cells: [(Int, Int)]) -> ArrowPiece { ArrowPiece(id, cells.map { ArrowCell($0.0, $0.1) }) }
}

final class ArrowLevel: PackLevel {
    let id: Int
    let tier: DifficultyTier
    let w: Int
    let h: Int
    let pic: String?
    let a: [String]
    let tip: String?

    init(_ id: Int, _ tier: DifficultyTier, _ w: Int, _ h: Int, _ pic: String?, _ a: [String], _ tip: String?) {
        self.id = id
        self.tier = tier
        self.w = w
        self.h = h
        self.pic = pic
        self.a = a
        self.tip = tip
    }

    var sizeLabel: String { "\(a.count) arrows" }

    var pieces: [ArrowPiece] {
        var out: [ArrowPiece] = []
        out.reserveCapacity(a.count)
        for (i, code) in a.enumerated() {
            if let p = ArrowPiece.parse(i, code) { out.append(p) }
        }
        return out
    }

    /// 0-based world (100 levels each).
    var world: Int { (id - 1) / 100 }

    static func parse(_ o: JSONObject) -> ArrowLevel {
        let arr = o.getJSONArray("a")
        let pic = o.optString("pic", "")
        let tip = o.optString("tip", "")
        return ArrowLevel(
            o.getInt("id"), DifficultyTier.parse(o.getString("tier")), o.getInt("w"), o.getInt("h"),
            pic.isEmpty ? nil : pic, (0..<arr.length()).map { arr.getString($0) }, tip.isEmpty ? nil : tip
        )
    }
}

/**
 * The rules: an arrow may leave only when every cell ahead of its head, up to the edge of the
 * picture, is free of other arrows. Removing an arrow only frees cells, so a greedy sweep
 * always finds a solution when one exists.
 */
final class ArrowBoard {
    enum TapResult: Equatable {
        case Exited
        case Blocked(by: Int, distance: Int)
        case None
    }

    let pieces: [ArrowPiece]
    let width: Int
    let height: Int
    private(set) var alive: [Bool]
    private(set) var remaining: Int
    private var owner: [Int]

    init(_ width: Int, _ height: Int, _ pieces: [ArrowPiece]) {
        self.pieces = pieces
        self.width = max(width, 1)
        self.height = max(height, 1)
        alive = [Bool](repeating: true, count: pieces.count)
        remaining = pieces.count
        owner = [Int](repeating: -1, count: self.width * self.height)
        for p in pieces {
            for c in p.cells where contains(c) { owner[c.r * self.width + c.c] = p.id }
        }
    }

    convenience init(_ level: ArrowLevel) { self.init(level.w, level.h, level.pieces) }

    /// A copy with the same state (what Kotlin's `copy()` rebuilds by re-adding and removing arrows;
    /// removals only clear their own cells, so copying the arrays is the same board).
    private init(copying b: ArrowBoard) {
        pieces = b.pieces
        width = b.width
        height = b.height
        alive = b.alive
        remaining = b.remaining
        owner = b.owner
    }

    var isCleared: Bool { remaining == 0 }

    @inline(__always)
    func contains(_ c: ArrowCell) -> Bool { c.r >= 0 && c.r < height && c.c >= 0 && c.c < width }

    func piece(_ at: ArrowCell) -> Int? {
        if !contains(at) { return nil }
        let id = owner[at.r * width + at.c]
        return id >= 0 ? id : nil
    }

    /// The first other arrow in `id`'s lane and how many free cells lie before it.
    func blocker(_ id: Int) -> (first: Int, second: Int)? {
        let p = pieces[id]
        let dr = p.heading.dr, dc = p.heading.dc
        let head = p.head
        var r = head.r + dr, c = head.c + dc
        var distance = 0
        while r >= 0 && r < height && c >= 0 && c < width {
            let other = owner[r * width + c]
            if other >= 0 && other != id { return (other, distance) }
            r += dr
            c += dc
            distance += 1
        }
        return nil
    }

    /// Free cells from the head to the edge.
    func laneLength(_ id: Int) -> Int {
        let p = pieces[id]
        switch p.heading {
        case .Up: return p.head.r
        case .Down: return height - 1 - p.head.r
        case .Left: return p.head.c
        case .Right: return width - 1 - p.head.c
        }
    }

    func canExit(_ id: Int) -> Bool { alive[id] && blocker(id) == nil }

    func tap(_ id: Int) -> TapResult {
        if id < 0 || id >= pieces.count || !alive[id] { return .None }
        if let b = blocker(id) { return .Blocked(by: b.first, distance: b.second) }
        remove(id)
        return .Exited
    }

    /// Removes `id` whatever is in its way (the hammer).
    func remove(_ id: Int) {
        if id < 0 || id >= pieces.count || !alive[id] { return }
        alive[id] = false
        remaining -= 1
        for c in pieces[id].cells where contains(c) {
            let i = c.r * width + c.c
            if owner[i] == id { owner[i] = -1 }
        }
    }

    var freeArrows: [Int] { pieces.indices.filter(canExit) }

    func copy() -> ArrowBoard { ArrowBoard(copying: self) }

    /// A full clearing order, or nil if the board is stuck.
    func solutionOrder() -> [Int]? {
        let board = copy()
        var order: [Int] = []
        while !board.isCleared {
            let free = board.freeArrows
            if free.isEmpty { return nil }
            for id in free {
                board.remove(id)
                order.append(id)
            }
        }
        return order
    }

    /// The best arrow to hint: a free one whose removal frees the most others.
    ///
    /// Kotlin tries each free arrow on a copy and counts the blocked arrows that become free. Removing
    /// `x` frees a blocked arrow exactly when `x` is the only other arrow in its lane, so the gains are
    /// counted in one pass over the lanes; the pick (first free arrow with the highest gain) is the same.
    func bestHint() -> Int? {
        let free = freeArrows
        if free.count <= 1 { return free.first }
        var gain = [Int](repeating: 0, count: pieces.count)
        for b in pieces.indices where alive[b] {
            let p = pieces[b]
            let dr = p.heading.dr, dc = p.heading.dc
            var r = p.head.r + dr, c = p.head.c + dc
            var only = -1
            var several = false
            while r >= 0 && r < height && c >= 0 && c < width {
                let o = owner[r * width + c]
                if o >= 0 && o != b {
                    if only < 0 { only = o } else if o != only { several = true; break }
                }
                r += dr
                c += dc
            }
            if only >= 0 && !several { gain[only] += 1 }
        }
        var best: (first: Int, second: Int)?
        for id in free where best == nil || gain[id] > best!.second { best = (id, gain[id]) }
        return best?.first
    }
}
