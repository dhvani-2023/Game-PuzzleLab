import Foundation
import GameKit

/// The app's only storage: one preferences file, `"puzzlelab"`, with values as strings, ints or JSON.
/// Keys are the Android ones (stored in UserDefaults as `puzzlelab.<key>` through GameKit `Prefs`).
enum Prefs {
    /// The underlying store (Android's `SharedPreferences`); `Prefs.sp.contains(key)` works as on Android.
    static let sp = GameKit.Prefs(name: "puzzlelab")

    static func string(_ key: String) -> String? { sp.optionalString(key) }

    static func putString(_ key: String, _ value: String?) {
        if let value { sp.set(key, value) } else { sp.remove(key) }
    }

    static func int(_ key: String, _ defaultValue: Int = 0) -> Int { sp.int(key, defaultValue) }
    static func putInt(_ key: String, _ value: Int) { sp.set(key, value) }

    static func long(_ key: String, _ defaultValue: Int64 = 0) -> Int64 { sp.long(key, defaultValue) }
    static func putLong(_ key: String, _ value: Int64) { sp.set(key, value) }

    static func bool(_ key: String, _ defaultValue: Bool = false) -> Bool { sp.bool(key, defaultValue) }
    static func putBool(_ key: String, _ value: Bool) { sp.set(key, value) }

    static func contains(_ key: String) -> Bool { sp.contains(key) }
    static func remove(_ key: String) { sp.remove(key) }

    /// Every key in the file (without the `puzzlelab.` prefix).
    static func keys() -> Set<String> {
        let prefix = "puzzlelab."
        var out = Set<String>()
        for k in sp.defaults.dictionaryRepresentation().keys where k.hasPrefix(prefix) {
            out.insert(String(k.dropFirst(prefix.count)))
        }
        return out
    }
}

/// Calendar days, counted in the device's time zone so "today" flips at local midnight.
enum Days {
    private static let msPerDay: Int64 = 86_400_000

    /// Days since 2001-01-01 (Apple's reference date), the numbering the iOS app has always used.
    static func dayNumber(_ timeMillis: Int64 = nowMillis()) -> Int {
        let date = Date(timeIntervalSince1970: Double(timeMillis) / 1000)
        let offset = Int64(TimeZone.current.secondsFromGMT(for: date)) * 1000
        let local = timeMillis + offset - 978_307_200_000
        return Int(floorDiv(local, msPerDay))
    }

    /// yyyyMMdd for the local date, used to seed daily boards.
    static func ymd(_ timeMillis: Int64 = nowMillis()) -> Int {
        let date = Date(timeIntervalSince1970: Double(timeMillis) / 1000)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 1970) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    static func hourOfDay() -> Int { Calendar.current.component(.hour, from: Date()) }

    /// Monday-first weekday index 0…6 for `day` (a `dayNumber`). 2001-01-01 was a Monday.
    static func weekdayIndex(_ day: Int) -> Int { ((day % 7) + 7) % 7 }

    static func nowMillis() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }

    // GameKit `Days` helpers, for code written against those names.
    static func epochDay(_ date: Date = Date()) -> Int { GameKit.Days.epochDay(date) }
    static func yyyymmdd(_ date: Date = Date()) -> Int { GameKit.Days.yyyymmdd(date) }

    private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
    }
}
