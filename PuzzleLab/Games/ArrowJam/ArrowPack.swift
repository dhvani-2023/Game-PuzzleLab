import Foundation

/**
 * Arrow Jam's level packs (`arrowjam_levels.json` is 7.6 MB, 3,000 boards and 390k arrow codes).
 * The same API as the shared `LevelPack`, but decoded by a byte scanner instead of
 * `JSONSerialization` (about 20× faster), off the main thread, and kept for the whole run.
 */
final class ArrowLevelPack: LevelCatalog, @unchecked Sendable {
    private struct Loaded {
        let version: Int
        let levels: [ArrowLevel]
        let ranges: [DifficultyTier: ClosedRange<Int>]
    }

    private let resource: String
    private let lock = NSLock()
    private var loaded: Loaded?

    init(_ resource: String) { self.resource = resource }

    private var data: Loaded {
        lock.lock()
        defer { lock.unlock() }
        if let loaded { return loaded }
        let l = load()
        loaded = l
        return l
    }

    private func load() -> Loaded {
        var version = 1
        var levels: [ArrowLevel] = []
        if let url = ArrowLevelPack.url(resource), let bytes = try? Data(contentsOf: url, options: .mappedIfSafe) {
            if let parsed = ArrowPackReader.read(bytes) {
                version = parsed.version
                levels = parsed.levels
            } else if let root = JSONObject(data: bytes) {
                // Not the expected shape: fall back to the generic org.json-style parser.
                version = root.optInt("version", 1)
                let array = root.getJSONArray("levels")
                levels = (0..<array.length()).map { ArrowLevel.parse(array.getJSONObject($0)) }
            }
        }
        levels.sort { $0.id < $1.id }
        var ranges: [DifficultyTier: ClosedRange<Int>] = [:]
        for level in levels {
            if let current = ranges[level.tier] {
                ranges[level.tier] = min(current.lowerBound, level.id)...max(current.upperBound, level.id)
            } else {
                ranges[level.tier] = level.id...level.id
            }
        }
        return Loaded(version: version, levels: levels, ranges: ranges)
    }

    /// Where packs are looked up (tests may add a directory bundle).
    nonisolated(unsafe) static var searchBundles: [Bundle] = [Bundle.main, Bundle(for: ArrowLevelPack.self)]

    static func url(_ resource: String) -> URL? {
        for bundle in searchBundles {
            for sub in [nil, "Levels", "levels", "Resources/Levels"] as [String?] {
                if let u = bundle.url(forResource: resource, withExtension: "json", subdirectory: sub) { return u }
            }
        }
        return nil
    }

    /// Decodes the pack now (call off the main thread to warm it up).
    func preload() { _ = data }

    var levels: [ArrowLevel] { data.levels }
    var version: Int { data.version }
    var count: Int { data.levels.count }
    var tiers: [DifficultyTier] { DifficultyTier.entries.filter { data.ranges[$0] != nil } }

    func level(_ id: Int) -> ArrowLevel? {
        let l = data.levels
        return id >= 1 && id <= l.count ? l[id - 1] : nil
    }

    func tier(_ level: Int) -> DifficultyTier? { self.level(level)?.tier }
    func range(_ tier: DifficultyTier) -> ClosedRange<Int>? { data.ranges[tier] }
    func sizeLabel(_ level: Int) -> String { self.level(level)?.sizeLabel ?? "" }
}

/// Reads `{"version":1,"levels":[{"id","tier","w","h","pic","a":[…],"tip"}…]}` straight from UTF-8 bytes.
enum ArrowPackReader {
    static func read(_ data: Data) -> (version: Int, levels: [ArrowLevel])? {
        data.withUnsafeBytes { raw -> (version: Int, levels: [ArrowLevel])? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var s = PackScanner(UnsafeBufferPointer(start: base, count: raw.count))
            return s.readArrowPack()
        }
    }
}

/// A minimal forward-only JSON reader over bytes: enough for the level packs, tolerant of
/// whitespace, key order, escapes and unknown keys.
struct PackScanner {
    let p: UnsafeBufferPointer<UInt8>
    var i = 0

    init(_ p: UnsafeBufferPointer<UInt8>) { self.p = p }

    @inline(__always)
    mutating func ws() {
        while i < p.count {
            let b = p[i]
            if b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09 { i += 1 } else { break }
        }
    }

    @inline(__always)
    mutating func eat(_ b: UInt8) -> Bool {
        ws()
        if i < p.count && p[i] == b { i += 1; return true }
        return false
    }

    mutating func peek() -> UInt8? {
        ws()
        return i < p.count ? p[i] : nil
    }

    /// A JSON string (the opening quote must be next).
    mutating func string() -> String? {
        guard eat(0x22) else { return nil }
        let start = i
        var escaped = false
        while i < p.count {
            let b = p[i]
            if b == 0x22 { break }
            if b == 0x5C { escaped = true; i += 2; continue }
            i += 1
        }
        guard i < p.count else { return nil }
        let end = i
        i += 1
        if !escaped { return String(decoding: UnsafeBufferPointer(rebasing: p[start..<end]), as: UTF8.self) }
        return PackScanner.unescape(UnsafeBufferPointer(rebasing: p[start..<end]))
    }

    /// Byte range of a JSON string without decoding it (the opening quote must be next).
    mutating func rawString() -> Range<Int>? {
        guard eat(0x22) else { return nil }
        let start = i
        while i < p.count {
            let b = p[i]
            if b == 0x22 { break }
            if b == 0x5C { return nil }
            i += 1
        }
        guard i < p.count else { return nil }
        let end = i
        i += 1
        return start..<end
    }

    private static func unescape(_ s: UnsafeBufferPointer<UInt8>) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(s.count)
        var k = 0
        func hex4(_ at: Int) -> UInt32? {
            guard at + 4 <= s.count else { return nil }
            var v: UInt32 = 0
            for j in at..<(at + 4) {
                let c = s[j]
                let d: UInt32
                switch c {
                case 0x30...0x39: d = UInt32(c - 0x30)
                case 0x41...0x46: d = UInt32(c - 0x41 + 10)
                case 0x61...0x66: d = UInt32(c - 0x61 + 10)
                default: return nil
                }
                v = v * 16 + d
            }
            return v
        }
        while k < s.count {
            let b = s[k]
            if b != 0x5C || k + 1 >= s.count { out.append(b); k += 1; continue }
            let e = s[k + 1]
            k += 2
            switch e {
            case 0x6E: out.append(0x0A)
            case 0x74: out.append(0x09)
            case 0x72: out.append(0x0D)
            case 0x62: out.append(0x08)
            case 0x66: out.append(0x0C)
            case 0x75:
                guard var scalar = hex4(k) else { continue }
                k += 4
                if scalar >= 0xD800 && scalar < 0xDC00, k + 6 <= s.count, s[k] == 0x5C, s[k + 1] == 0x75, let low = hex4(k + 2),
                   low >= 0xDC00 && low < 0xE000 {
                    scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    k += 6
                }
                let u = Unicode.Scalar(scalar) ?? "\u{FFFD}"
                out.append(contentsOf: Array(String(Character(u)).utf8))
            default: out.append(e)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// A JSON number as Double (ints stay exact up to 2^53).
    mutating func number() -> Double? {
        ws()
        let start = i
        var isInt = true
        var v = 0
        var negative = false
        if i < p.count && p[i] == 0x2D { negative = true; i += 1 }
        while i < p.count {
            let b = p[i]
            if b >= 0x30 && b <= 0x39 {
                v = v &* 10 &+ Int(b - 0x30)
                i += 1
            } else if b == 0x2E || b == 0x65 || b == 0x45 || b == 0x2B || b == 0x2D {
                isInt = false
                i += 1
            } else {
                break
            }
        }
        guard i > start else { return nil }
        if isInt { return Double(negative ? -v : v) }
        return Double(String(decoding: UnsafeBufferPointer(rebasing: p[start..<i]), as: UTF8.self))
    }

    /// org.json `getInt`: numbers truncate toward zero.
    mutating func int() -> Int? {
        guard let d = number() else { return nil }
        return Int(exactly: d.rounded(.towardZero)) ?? 0
    }

    /// Skips any JSON value.
    mutating func skipValue() -> Bool {
        guard let b = peek() else { return false }
        switch b {
        case 0x22: return string() != nil
        case 0x7B:
            i += 1
            if eat(0x7D) { return true }
            repeat {
                guard string() != nil, eat(0x3A), skipValue() else { return false }
            } while eat(0x2C)
            return eat(0x7D)
        case 0x5B:
            i += 1
            if eat(0x5D) { return true }
            repeat {
                guard skipValue() else { return false }
            } while eat(0x2C)
            return eat(0x5D)
        case 0x74: i += 4; return true   // true
        case 0x66: i += 5; return true   // false
        case 0x6E: i += 4; return true   // null
        default: return number() != nil
        }
    }

    /// `["a","b",…]` as Strings.
    mutating func stringArray() -> [String]? {
        guard eat(0x5B) else { return nil }
        var out: [String] = []
        if eat(0x5D) { return out }
        repeat {
            guard let s = string() else { return nil }
            out.append(s)
        } while eat(0x2C)
        return eat(0x5D) ? out : nil
    }

    /// `[1,2,…]` as Ints.
    mutating func intArray() -> [Int]? {
        guard eat(0x5B) else { return nil }
        var out: [Int] = []
        if eat(0x5D) { return out }
        repeat {
            guard let v = int() else { return nil }
            out.append(v)
        } while eat(0x2C)
        return eat(0x5D) ? out : nil
    }

    /// Iterates the members of an object; `body` must consume each value. Returns false on bad JSON.
    mutating func object(_ body: (inout PackScanner, String) -> Bool) -> Bool {
        guard eat(0x7B) else { return false }
        if eat(0x7D) { return true }
        repeat {
            guard let key = string(), eat(0x3A), body(&self, key) else { return false }
        } while eat(0x2C)
        return eat(0x7D)
    }

    /// Iterates the elements of an array; `body` must consume each element.
    mutating func array(_ body: (inout PackScanner) -> Bool) -> Bool {
        guard eat(0x5B) else { return false }
        if eat(0x5D) { return true }
        repeat {
            guard body(&self) else { return false }
        } while eat(0x2C)
        return eat(0x5D)
    }

    // MARK: Arrow Jam

    mutating func readArrowPack() -> (version: Int, levels: [ArrowLevel])? {
        var version = 1
        var levels: [ArrowLevel] = []
        let ok = object { s, key in
            switch key {
            case "version":
                guard let v = s.int() else { return false }
                version = v
                return true
            case "levels":
                return s.array { s in
                    guard let level = s.readArrowLevel() else { return false }
                    levels.append(level)
                    return true
                }
            default:
                return s.skipValue()
            }
        }
        return ok ? (version, levels) : nil
    }

    private mutating func readArrowLevel() -> ArrowLevel? {
        var id = 0, w = 0, h = 0
        var tier = "", pic = "", tip = ""
        var a: [String] = []
        let ok = object { s, key in
            switch key {
            case "id": if let v = s.int() { id = v; return true }; return false
            case "w": if let v = s.int() { w = v; return true }; return false
            case "h": if let v = s.int() { h = v; return true }; return false
            case "tier": if let v = s.string() { tier = v; return true }; return s.skipValue()
            case "pic": if s.peek() == 0x22, let v = s.string() { pic = v; return true }; return s.skipValue()
            case "tip": if s.peek() == 0x22, let v = s.string() { tip = v; return true }; return s.skipValue()
            case "a": if let v = s.stringArray() { a = v; return true }; return false
            default: return s.skipValue()
            }
        }
        guard ok else { return nil }
        return ArrowLevel(id, DifficultyTier.parse(tier), w, h, pic.isEmpty ? nil : pic, a, tip.isEmpty ? nil : tip)
    }
}
