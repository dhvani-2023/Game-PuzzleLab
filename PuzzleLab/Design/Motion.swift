import SwiftUI
import UIKit
import GameKit

/// SwiftUI's `spring(response:dampingFraction:)` — the curve Android's `labSpring` re-creates in Compose
/// (stiffness = (2π / response)², same damping ratio).
func labSpring(_ response: Double, _ damping: Double) -> Animation {
    .spring(response: response, dampingFraction: damping)
}

func labSpring(response: Double, damping: Double) -> Animation { labSpring(response, damping) }

/// Compose `tween(ms, easing = FastOutSlowInEasing)` (the Compose default easing).
func tween(_ ms: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: ms / 1000) }
/// Compose `tween(ms, easing = LinearEasing)`.
func linearTween(_ ms: Double) -> Animation { .linear(duration: ms / 1000) }

/// Night Lab motion tokens: every shell animation uses one of these.
enum Motion {
    static var snappy: Animation { labSpring(0.28, 0.72) }
    static var bouncy: Animation { labSpring(0.42, 0.6) }
    static var gentle: Animation { labSpring(0.6, 0.88) }
    static var hero: Animation { labSpring(0.5, 0.86) }

    /// Delay (ms) for the `index`th item of a list appearing; capped so long lists don't drag.
    static func stagger(_ index: Int) -> Int { min(max(index, 0), 8) * 40 }

    /// Reduce Motion for the app (Settings › Reduce motion, else the system setting).
    static var reduce: Bool { LabTheme.shared.reduceMotion }
    static var appReduceMotion: Bool { LabTheme.shared.reduceMotion }
}

/// The haptic vocabulary, so the same action always feels the same. Follows the Haptics setting.
/// Safe to call from any thread (GameKit's generators run on the main actor).
enum Haptics {
    private static var settings: AppSettings?

    /// Kotlin `Haptics.init(context, settings)`.
    static func setup(_ settings: AppSettings) {
        self.settings = settings
        syncEnabled()
        onMain { GameKit.Haptics.prepare() }
    }

    static var enabled: Bool { settings?.hapticsEnabled != false }

    static func syncEnabled() {
        let on = enabled
        onMain { GameKit.Haptics.enabled = on }
    }

    private static func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }

    private static func run(_ body: @escaping @MainActor () -> Void) {
        guard enabled else { return }
        onMain(body)
    }

    /// Selection change (tabs, chips, dragging over cells).
    static func selection() { run { GameKit.Haptics.tick() } }
    static func tap() { selection() }
    static func toggle() { impactLight() }
    static func cta() { impactMedium() }
    static func impactLight() { run { GameKit.Haptics.tap(0.6) } }
    static func impactMedium() { run { GameKit.Haptics.medium(0.85) } }
    static func impactHeavy() { run { GameKit.Haptics.heavy(1) } }
    static func success() { run { GameKit.Haptics.success() } }
    static func warning() { run { GameKit.Haptics.warning() } }
    static func error() { run { GameKit.Haptics.error() } }
    static func rumble(_ ms: Int = 40) { run { GameKit.Haptics.pattern(timings: [0, ms], amplitudes: [0, 200]) } }

    // GameKit spellings, for code written against GameKit's `Haptics`.
    static func tick() { selection() }
    static func tap(_ intensity: CGFloat) { run { GameKit.Haptics.tap(intensity) } }
    static func softTap(_ intensity: CGFloat = 0.7) { run { GameKit.Haptics.softTap(intensity) } }
    static func rigidTap(_ intensity: CGFloat = 0.8) { run { GameKit.Haptics.rigidTap(intensity) } }
    static func medium(_ intensity: CGFloat = 1) { run { GameKit.Haptics.medium(intensity) } }
    static func heavy(_ intensity: CGFloat = 1) { run { GameKit.Haptics.heavy(intensity) } }
    static func pattern(timings: [Int], amplitudes: [Int]) { run { GameKit.Haptics.pattern(timings: timings, amplitudes: amplitudes) } }
    static func prepare() { onMain { GameKit.Haptics.prepare() } }
}
