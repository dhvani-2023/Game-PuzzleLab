import Foundation

/// A read/write JSON object with org.json's API (`getInt`, `optString`, `getJSONArray`, `put`…), so the
/// Kotlin level-pack parsers and save encoders port line for line. Backed by `JSONSerialization` values.
struct JSONObject {
    private(set) var map: [String: Any]
    /// Key order as written by `put`; nil for parsed objects (then keys come back sorted).
    private var order: [String]?

    init() { map = [:]; order = [] }

    init(_ map: [String: Any]) {
        self.map = map
        order = nil
    }

    /// Parses JSON text; nil when it isn't a JSON object (Kotlin: `runCatching { JSONObject(it) }.getOrNull()`).
    init?(string: String) {
        guard let data = string.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any]
        else { return nil }
        self.init(obj)
    }

    init?(data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        self.init(obj)
    }

    func has(_ key: String) -> Bool { if let v = map[key] { return !(v is NSNull) } else { return false } }
    func keys() -> [String] { order.map { o in o.filter { map[$0] != nil } } ?? map.keys.sorted() }
    func length() -> Int { map.count }

    func getInt(_ key: String) -> Int { JSONValue.int(map[key]) ?? 0 }
    func optInt(_ key: String, _ fallback: Int = 0) -> Int { JSONValue.int(map[key]) ?? fallback }
    func getLong(_ key: String) -> Int64 { JSONValue.long(map[key]) ?? 0 }
    func optLong(_ key: String, _ fallback: Int64 = 0) -> Int64 { JSONValue.long(map[key]) ?? fallback }
    func getDouble(_ key: String) -> Double { JSONValue.double(map[key]) ?? 0 }
    func optDouble(_ key: String, _ fallback: Double = .nan) -> Double { JSONValue.double(map[key]) ?? fallback }
    func getBoolean(_ key: String) -> Bool { JSONValue.bool(map[key]) ?? false }
    func optBoolean(_ key: String, _ fallback: Bool = false) -> Bool { JSONValue.bool(map[key]) ?? fallback }
    func getString(_ key: String) -> String { JSONValue.string(map[key]) ?? "" }
    func optString(_ key: String, _ fallback: String = "") -> String { JSONValue.string(map[key]) ?? fallback }
    func getJSONArray(_ key: String) -> JSONArray { optJSONArray(key) ?? JSONArray() }
    func optJSONArray(_ key: String) -> JSONArray? { (map[key] as? [Any]).map(JSONArray.init) }
    func getJSONObject(_ key: String) -> JSONObject { optJSONObject(key) ?? JSONObject() }
    func optJSONObject(_ key: String) -> JSONObject? { (map[key] as? [String: Any]).map(JSONObject.init) }
    func opt(_ key: String) -> Any? { map[key] }

    @discardableResult
    mutating func put(_ key: String, _ value: Any?) -> JSONObject {
        if order == nil { order = map.keys.sorted() }
        if map[key] == nil { order?.append(key) }
        map[key] = JSONValue.raw(value)
        return self
    }

    /// Builder-style `put` for chains: `JSONObject().putting("t", 3).putting("s", 2)`.
    func putting(_ key: String, _ value: Any?) -> JSONObject {
        var copy = self
        copy.put(key, value)
        return copy
    }

    mutating func remove(_ key: String) {
        map[key] = nil
        order?.removeAll { $0 == key }
    }

    /// Compact JSON text, like `JSONObject.toString()`.
    func toString() -> String { JSONValue.text(map) }
}

/// org.json `JSONArray`.
struct JSONArray {
    private(set) var items: [Any]

    init() { items = [] }
    init(_ items: [Any]) { self.items = items }
    init<T>(values: [T]) { items = values.map { JSONValue.raw($0) ?? NSNull() } }

    init?(string: String) {
        guard let data = string.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return nil }
        items = arr
    }

    func length() -> Int { items.count }
    private func at(_ i: Int) -> Any? { i >= 0 && i < items.count ? items[i] : nil }

    func getInt(_ i: Int) -> Int { JSONValue.int(at(i)) ?? 0 }
    func optInt(_ i: Int, _ fallback: Int = 0) -> Int { JSONValue.int(at(i)) ?? fallback }
    func getLong(_ i: Int) -> Int64 { JSONValue.long(at(i)) ?? 0 }
    func getDouble(_ i: Int) -> Double { JSONValue.double(at(i)) ?? 0 }
    func getBoolean(_ i: Int) -> Bool { JSONValue.bool(at(i)) ?? false }
    func getString(_ i: Int) -> String { JSONValue.string(at(i)) ?? "" }
    func optString(_ i: Int, _ fallback: String = "") -> String { JSONValue.string(at(i)) ?? fallback }
    func getJSONArray(_ i: Int) -> JSONArray { (at(i) as? [Any]).map(JSONArray.init) ?? JSONArray() }
    func optJSONArray(_ i: Int) -> JSONArray? { (at(i) as? [Any]).map(JSONArray.init) }
    func getJSONObject(_ i: Int) -> JSONObject { (at(i) as? [String: Any]).map(JSONObject.init) ?? JSONObject() }
    func optJSONObject(_ i: Int) -> JSONObject? { (at(i) as? [String: Any]).map(JSONObject.init) }

    @discardableResult
    mutating func put(_ value: Any?) -> JSONArray {
        items.append(JSONValue.raw(value) ?? NSNull())
        return self
    }

    func toString() -> String { JSONValue.text(items) }
}

/// Lenient conversions with org.json's coercions (numbers ↔ strings, doubles → ints).
enum JSONValue {
    static func int(_ v: Any?) -> Int? {
        switch v {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? Double(s).map { Int($0) }
        default: return nil
        }
    }

    static func long(_ v: Any?) -> Int64? {
        switch v {
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s) ?? Double(s).map { Int64($0) }
        default: return nil
        }
    }

    static func double(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func bool(_ v: Any?) -> Bool? {
        switch v {
        case let n as NSNumber: return n.boolValue
        case let s as String: return s.lowercased() == "true" ? true : (s.lowercased() == "false" ? false : nil)
        default: return nil
        }
    }

    static func string(_ v: Any?) -> String? {
        switch v {
        case nil, is NSNull: return nil
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let o as [String: Any]: return text(o)
        case let a as [Any]: return text(a)
        default: return "\(v!)"
        }
    }

    /// Unwraps the Swift wrappers so values can go into `JSONSerialization`.
    static func raw(_ v: Any?) -> Any? {
        switch v {
        case nil: return nil
        case let o as JSONObject: return o.map
        case let a as JSONArray: return a.items
        case let i as Int: return NSNumber(value: i)
        case let i as Int64: return NSNumber(value: i)
        case let i as Int32: return NSNumber(value: i)
        case let d as Double: return NSNumber(value: d)
        case let f as Float: return NSNumber(value: Double(f))
        case let b as Bool: return NSNumber(value: b)
        case let a as [Int]: return a.map { NSNumber(value: $0) }
        case let a as [String]: return a
        default: return v
        }
    }

    static func text(_ v: Any) -> String {
        guard JSONSerialization.isValidJSONObject(v),
              let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "{}" }
        return String(data: d, encoding: .utf8) ?? "{}"
    }
}
