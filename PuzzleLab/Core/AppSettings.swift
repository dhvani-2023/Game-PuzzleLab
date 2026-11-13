import Foundation
import Observation

/// App-wide look and comfort settings, stored on the device. Dark is the starting look.
@Observable
final class AppSettings {
    enum Theme: String, CaseIterable {
        case System, Light, Dark

        var title: String { rawValue }
        static var entries: [Theme] { allCases }
    }

    enum MotionPreference: String, CaseIterable {
        case System, Reduced, Full

        var title: String {
            switch self {
            case .System: return "System"
            case .Reduced: return "On"
            case .Full: return "Off"
            }
        }

        static var entries: [MotionPreference] { allCases }
    }

    private(set) var theme: Theme = .Dark
    private(set) var motion: MotionPreference = .System
    private(set) var soundEnabled = true
    private(set) var hapticsEnabled = true
    private(set) var hasCompletedOnboarding = false
    /// Bumped when progress is reset, so screens that cache derived values refresh.
    var resetToken = 0

    @ObservationIgnored private static let key = "app.settings.v1"

    init() {
        if let raw = Prefs.string(Self.key), let o = JSONObject(string: raw) {
            theme = Theme(rawValue: o.optString("theme")) ?? .Dark
            motion = MotionPreference(rawValue: o.optString("motion")) ?? .System
            soundEnabled = o.optBoolean("sound", true)
            hapticsEnabled = o.optBoolean("haptics", true)
        }
        hasCompletedOnboarding = Prefs.bool("hasCompletedOnboarding")
    }

    func updateTheme(_ value: Theme) { theme = value; save() }
    func updateMotion(_ value: MotionPreference) { motion = value; save() }
    func updateSound(_ value: Bool) { soundEnabled = value; save() }
    func updateHaptics(_ value: Bool) {
        hapticsEnabled = value
        save()
        Haptics.syncEnabled()
    }

    func setOnboardingDone(_ done: Bool) {
        hasCompletedOnboarding = done
        Prefs.putBool("hasCompletedOnboarding", done)
    }

    /// Reduce Motion for the app: the system setting unless Settings overrides it.
    func reducesMotion(_ system: Bool) -> Bool {
        switch motion {
        case .System: return system
        case .Reduced: return true
        case .Full: return false
        }
    }

    private func save() {
        let o = JSONObject()
            .putting("theme", theme.rawValue)
            .putting("motion", motion.rawValue)
            .putting("sound", soundEnabled)
            .putting("haptics", hapticsEnabled)
        Prefs.putString(Self.key, o.toString())
    }
}
