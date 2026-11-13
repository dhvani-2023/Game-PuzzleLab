import Foundation
import GameKit

/// Plays synthesized buffers through GameKit's voice pool on the shared 48 kHz `AVAudioEngine`. Like the
/// Android mixer, up to 12 voices overlap and the oldest is dropped beyond that.
enum SoundEngine {
    private static let MAX_VOICES = 12
    private static var settings: AppSettings?
    private static var bank: GameKit.SoundBank?
    private static let lock = NSLock()

    /// Kotlin `SoundEngine.init(settings)`: wires the Sound setting and starts the audio engine.
    static func setup(_ settings: AppSettings) {
        self.settings = settings
        if bank == nil {
            bank = GameKit.SoundBank(voices: MAX_VOICES)
            AudioSystem.shared.start()
        }
    }

    static var enabled: Bool { settings?.soundEnabled != false }

    /// Registers `samples` under `name` once, then plays it at `gain`.
    static func play(_ name: String, _ samples: () -> [Float], _ gain: Float) {
        guard enabled, let bank else { return }
        lock.lock()
        let known = bank.has(name)
        if !known {
            let s = samples()
            if !s.isEmpty { bank.register(name, samples: s) }
        }
        lock.unlock()
        bank.play(name, volume: gain)
    }

    static func prepare(_ name: String, _ samples: () -> [Float]) {
        guard let bank else { return }
        lock.lock()
        defer { lock.unlock() }
        if !bank.has(name) {
            let s = samples()
            if !s.isEmpty { bank.register(name, samples: s) }
        }
    }
}

/// A family of cached effects with a master gain and per-effect throttling (Kotlin `SoundBank<E>`).
class SoundBank<E: Hashable> {
    private let gain: Float
    private let prefix: String
    private var lastPlayed: [E: Int64] = [:]
    private let lock = NSLock()

    init(gain: Float, name: String) {
        self.gain = gain
        self.prefix = name
    }

    /// Builds one effect's samples; subclasses override.
    func synthesize(_ effect: E) -> [Float] { [] }

    private func key(_ effect: E) -> String { "\(prefix).\(String(describing: effect))" }

    func play(_ effect: E, _ throttleMs: Int64 = 30) {
        guard SoundEngine.enabled else { return }
        let now = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        lock.lock()
        if let last = lastPlayed[effect], now - last < throttleMs {
            lock.unlock()
            return
        }
        lastPlayed[effect] = now
        lock.unlock()
        SoundEngine.play(key(effect), { Synth.clamp(synthesize(effect)) }, gain)
    }

    /// Labelled form of `play` for Swift call sites.
    func play(_ effect: E, throttleMs: Int64) { play(effect, throttleMs) }

    /// Builds buffers ahead of time so the first move doesn't stutter.
    func warmUp(_ effects: [E]) {
        for e in effects { SoundEngine.prepare(key(e), { Synth.clamp(synthesize(e)) }) }
    }
}
