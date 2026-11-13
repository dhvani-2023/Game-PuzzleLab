import Foundation

/// The games' synthesizer, ported line for line from Android (itself the iOS `TileSound`/`ArrowSound`/
/// `UISound` synth): a note gliding between two frequencies with a short attack and an exponential decay,
/// in five waveforms. Noise is an LCG through a one-pole low-pass that follows the frequency.
/// Renders at 48 kHz (Android: 44.1 kHz); every recipe is defined in seconds and Hz, so it sounds the same.
enum Synth {
    static let RATE: Double = 48_000

    enum Wave { case sine, triangle, square, saw, noise }

    static func note(_ semitones: Int, _ base: Double = 523.25) -> Double { base * pow(2.0, Double(semitones) / 12.0) }

    static func silence(_ duration: Double) -> [Float] { [Float](repeating: 0, count: Int(duration * RATE)) }

    static func tone(_ frequency: Double, _ duration: Double, _ wave: Wave, volume: Float, decay: Double = 3.2, attack: Double = 0.004) -> [Float] {
        sweep(frequency, frequency, duration, wave, volume: volume, decay: decay, attack: attack)
    }

    static func sweep(_ start: Double, _ end: Double, _ duration: Double, _ wave: Wave, volume: Float, decay: Double = 3.2, attack: Double = 0.004) -> [Float] {
        let count = Int(duration * RATE)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        var seed: UInt64 = 0x9E37_79B9
        var lowpass = 0.0
        let span = Double(max(count - 1, 1))
        for i in 0..<count {
            let t = Double(i) / RATE
            let progress = Double(i) / span
            let frequency = start + (end - start) * progress
            phase += frequency / RATE
            let x = phase - phase.rounded(.down)
            let sample: Double
            switch wave {
            case .sine: sample = sin(2 * .pi * x)
            case .triangle: sample = 4 * abs(x - 0.5) - 1
            case .square: sample = x < 0.5 ? 1.0 : -1.0
            case .saw: sample = 2 * x - 1
            case .noise:
                seed = (seed &* 1_664_525 &+ 1_013_904_223) & 0xFFFF_FFFF
                let white = Double(seed) / 4_294_967_295.0 * 2 - 1
                lowpass += (white - lowpass) * min(1.0, max(0.02, frequency / RATE * 6))
                sample = lowpass * 1.6
            }
            let env = min(1.0, t / attack)
            out[i] = Float(sample * env * exp(-decay * progress)) * volume
        }
        return out
    }

    /// The UI sounds' variant: noise without the 0.02 floor and a 3 ms attack.
    static func uiSweep(_ start: Double, _ end: Double, _ duration: Double, noise: Bool, volume: Float) -> [Float] {
        let count = Int(duration * RATE)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        var seed: UInt64 = 0x9E37_79B9
        var low = 0.0
        let span = Double(max(count - 1, 1))
        for i in 0..<count {
            let t = Double(i) / RATE
            let p = Double(i) / span
            let f = start + (end - start) * p
            let sample: Double
            if noise {
                seed = (seed &* 1_664_525 &+ 1_013_904_223) & 0xFFFF_FFFF
                low += (Double(seed) / 4_294_967_295.0 * 2 - 1 - low) * min(1.0, f / RATE * 6)
                sample = low * 1.5
            } else {
                phase += f / RATE
                sample = sin(2 * .pi * phase)
            }
            out[i] = Float(sample * min(1.0, t / 0.003) * exp(-4 * p)) * volume
        }
        return out
    }

    static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: max(a.count, b.count))
        for i in 0..<out.count {
            out[i] = (i < a.count ? a[i] : 0) + (i < b.count ? b[i] : 0)
        }
        return out
    }

    static func concat(_ parts: [[Float]]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(parts.reduce(0) { $0 + $1.count })
        for p in parts { out.append(contentsOf: p) }
        return out
    }

    static func clamp(_ samples: [Float]) -> [Float] {
        samples.map { min(1, max(-1, $0)) }
    }
}
