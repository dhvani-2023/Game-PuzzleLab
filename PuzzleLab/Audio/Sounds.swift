import Foundation

// Kotlin `object X : SoundBank<X.Effect>` → `enum X` (static API: `X.play(.Effect)`, `X.tap()`, `X.warmUp()`)
// backed by one `SoundBank` subclass instance (`X.shared`). `a + b` on `[Float]` concatenates, as in Kotlin.


private func tone(_ f: Double, _ d: Double, _ w: Synth.Wave, volume: Float, decay: Double = 3.2) -> [Float] {
    Synth.tone(f, d, w, volume: volume, decay: decay)
}

private func sweep(_ a: Double, _ b: Double, _ d: Double, _ w: Synth.Wave, volume: Float, decay: Double = 3.2) -> [Float] {
    Synth.sweep(a, b, d, w, volume: volume, decay: decay)
}

private func note(_ s: Int, _ base: Double = 523.25) -> Double { Synth.note(s, base) }
private func mix(_ a: [Float], _ b: [Float]) -> [Float] { Synth.mix(a, b) }
private func silence(_ d: Double) -> [Float] { Synth.silence(d) }

// MARK: - UISound

enum UISoundEffect: Hashable {
    case Tap, Toggle, Whoosh, Sparkle
}

final class UISoundBank: SoundBank<UISoundEffect> {
    override func synthesize(_ effect: UISoundEffect) -> [Float] {
        switch effect {
        case .Tap: return Synth.uiSweep(1400, 1700, 0.035, noise: false, volume: 0.18)
        case .Toggle: return Synth.uiSweep(880, 1320, 0.05, noise: false, volume: 0.2)
        case .Whoosh: return Synth.uiSweep(500, 2600, 0.16, noise: true, volume: 0.1)
        case .Sparkle:
            return Synth.concat([0, 4, 7, 12].map { s in
                let f = 1046.5 * pow(2.0, Double(s) / 12.0)
                return Synth.uiSweep(f, f, 0.05, noise: false, volume: 0.14)
            })
        }
    }
}

/// Short, quiet interface sounds (the iOS `UISound`).
enum UISound {
    typealias Effect = UISoundEffect
    static let shared = UISoundBank(gain: 0.4, name: "ui")

    static func play(_ effect: Effect, _ throttleMs: Int64 = 30) { shared.play(effect, throttleMs) }
    static func tap() { play(.Tap, 50) }
    static func toggle() { play(.Toggle, 50) }
    static func whoosh() { play(.Whoosh, 50) }
    static func sparkle() { play(.Sparkle, 50) }
}

// MARK: - PuzzleSound

enum PuzzleSoundEffect: Hashable {
    /// A patch snapping in; bigger patches sit lower on the scale.
    case Place(Int)
    case Remove
    case Error
    /// One step of a Zip path, climbing a pentatonic scale.
    case Step(Int)
    case Dot(Int)
    case Hint
    case Clear
    case Solved
    case Star
    case Win

    static func place(size: Int) -> Self { .Place(size) }
    static func place(_ size: Int) -> Self { .Place(size) }
    static func step(step: Int) -> Self { .Step(step) }
    static func step(_ step: Int) -> Self { .Step(step) }
    static func dot(rank: Int) -> Self { .Dot(rank) }
    static func dot(_ rank: Int) -> Self { .Dot(rank) }
    static let remove = Self.Remove
    static let error = Self.Error
    static let hint = Self.Hint
    static let clear = Self.Clear
    static let solved = Self.Solved
    static let star = Self.Star
    static let win = Self.Win
}

final class PuzzleSoundBank: SoundBank<PuzzleSoundEffect> {
    private let pentatonic = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 31]

    override func synthesize(_ effect: PuzzleSoundEffect) -> [Float] {
        switch effect {
        case .Place(let size):
            let f = note(pentatonic[min(max(9 - min(max(size, 1), 9), 0), 8)], 392.0)
            return mix(mix(sweep(f * 0.6, f, 0.05, .sine, volume: 0.3, decay: 6.0), tone(f, 0.22, .sine, volume: 0.26, decay: 6.0)),
                       mix(tone(f * 2, 0.14, .sine, volume: 0.08, decay: 8.0), tone(3800.0, 0.015, .noise, volume: 0.1, decay: 8.0)))
        case .Remove:
            return sweep(900.0, 520.0, 0.08, .triangle, volume: 0.16, decay: 5.0)
        case .Error:
            return tone(330.0, 0.06, .triangle, volume: 0.24) + tone(247.0, 0.08, .triangle, volume: 0.22)
        case .Step(let step):
            let n = pentatonic.count
            let f = note(pentatonic[((step % n) + n) % n], 659.25)
            return mix(tone(f, 0.07, .sine, volume: 0.14, decay: 7.0), tone(f * 2, 0.05, .sine, volume: 0.04, decay: 9.0))
        case .Dot(let rank):
            let f = note(pentatonic[min(max(rank, 0), pentatonic.count - 1)], 784.0)
            return mix(mix(tone(f, 0.3, .sine, volume: 0.24, decay: 6.0), tone(f * 2, 0.2, .sine, volume: 0.08, decay: 8.0)),
                       silence(0.03) + tone(f * 1.5, 0.16, .triangle, volume: 0.06, decay: 6.0))
        case .Hint:
            return tone(note(7, 784.0), 0.1, .sine, volume: 0.2) + tone(note(12, 784.0), 0.22, .sine, volume: 0.18)
        case .Clear:
            return sweep(1200.0, 300.0, 0.22, .noise, volume: 0.08, decay: 2.5)
        case .Solved:
            return Synth.concat([0, 4, 7, 12, 16].map { tone(note($0, 1046.5), 0.05, .sine, volume: 0.16) })
                + tone(note(19, 1046.5), 0.28, .sine, volume: 0.13)
        case .Star:
            return tone(1568.0, 0.08, .triangle, volume: 0.26) + tone(2093.0, 0.22, .sine, volume: 0.24)
        case .Win:
            let melody: [(Int, Double)] = [(0, 0.1), (4, 0.1), (7, 0.1), (12, 0.14), (7, 0.08), (12, 0.36)]
            return mix(Synth.concat(melody.map { tone(note($0.0), $0.1, .triangle, volume: 0.3) }),
                       silence(0.55) + mix(tone(note(0), 0.5, .sine, volume: 0.15), tone(note(7), 0.5, .sine, volume: 0.12)))
        }
    }
}

/// Sounds for Patches and Zip, built with the same synth and scales as the other games.
enum PuzzleSound {
    typealias Effect = PuzzleSoundEffect
    static let shared = PuzzleSoundBank(gain: 0.5, name: "puzzle")

    static func play(_ effect: Effect, _ throttleMs: Int64 = 30) { shared.play(effect, throttleMs) }
    static func play(_ effect: Effect, throttleMs: Int64) { shared.play(effect, throttleMs) }
}

// MARK: - TileSound

enum TileSoundEffect: Hashable {
    case Pick, Place, Bounce, Deal
    case Clear(Int)
    case Multi, Combo, FeverStart, FeverEnd, Perfect, Gem, NewBest, GameOver, Revive, Win, Star, Tick

    static func clear(step: Int) -> Self { .Clear(step) }
    static func clear(_ step: Int) -> Self { .Clear(step) }
    static let pick = Self.Pick
    static let place = Self.Place
    static let bounce = Self.Bounce
    static let deal = Self.Deal
    static let multi = Self.Multi
    static let combo = Self.Combo
    static let feverStart = Self.FeverStart
    static let feverEnd = Self.FeverEnd
    static let perfect = Self.Perfect
    static let gem = Self.Gem
    static let newBest = Self.NewBest
    static let gameOver = Self.GameOver
    static let revive = Self.Revive
    static let win = Self.Win
    static let star = Self.Star
    static let tick = Self.Tick
}

final class TileSoundBank: SoundBank<TileSoundEffect> {
    private let pentatonic = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 31]

    override func synthesize(_ effect: TileSoundEffect) -> [Float] {
        switch effect {
        case .Pick:
            return tone(1760.0, 0.03, .sine, volume: 0.2)
        case .Place:
            return mix(sweep(240.0, 150.0, 0.09, .sine, volume: 0.55, decay: 5.0), tone(4000.0, 0.018, .noise, volume: 0.2, decay: 8.0))
        case .Bounce:
            return tone(330.0, 0.06, .triangle, volume: 0.26) + tone(247.0, 0.08, .triangle, volume: 0.24)
        case .Deal:
            return sweep(900.0, 2400.0, 0.12, .noise, volume: 0.09, decay: 2.0)
        case .Clear(let step):
            let f = note(pentatonic[min(max(step, 0), pentatonic.count - 1)], 659.25)
            return mix(mix(tone(f, 0.28, .sine, volume: 0.32, decay: 4.0), tone(f * 2, 0.2, .sine, volume: 0.12, decay: 6.0)),
                       sweep(5000.0, 1200.0, 0.12, .noise, volume: 0.05, decay: 4.0))
        case .Multi:
            return mix(mix(tone(note(0), 0.4, .triangle, volume: 0.22), tone(note(4), 0.4, .triangle, volume: 0.2)),
                       mix(tone(note(7), 0.4, .triangle, volume: 0.18), silence(0.06) + tone(note(12), 0.34, .sine, volume: 0.18)))
        case .Combo:
            return Synth.concat([0, 4, 7].map { tone(note($0, 784.0), 0.06, .triangle, volume: 0.24) })
                + tone(note(12, 784.0), 0.18, .sine, volume: 0.22)
        case .FeverStart:
            return mix(sweep(200.0, 1600.0, 0.5, .saw, volume: 0.1, decay: 0.8),
                       silence(0.35) + Synth.concat([0, 4, 7, 12, 16].map { tone(note($0, 1046.5), 0.05, .sine, volume: 0.18) }))
        case .FeverEnd:
            return sweep(1200.0, 300.0, 0.35, .triangle, volume: 0.16, decay: 2.0)
        case .Perfect:
            return Synth.concat([0, 4, 7, 11, 14, 19].map { tone(note($0, 1046.5), 0.06, .sine, volume: 0.2) })
                + tone(note(23, 1046.5), 0.3, .sine, volume: 0.16)
        case .Gem:
            return mix(tone(2093.0, 0.18, .sine, volume: 0.22, decay: 4.0), silence(0.04) + tone(3136.0, 0.16, .sine, volume: 0.14, decay: 5.0))
        case .NewBest:
            let melody: [(Int, Double)] = [(0, 0.1), (4, 0.1), (7, 0.1), (12, 0.12), (16, 0.1), (19, 0.36)]
            return Synth.concat(melody.map { tone(note($0.0), $0.1, .triangle, volume: 0.3) })
        case .GameOver:
            return tone(note(7, 392.0), 0.16, .triangle, volume: 0.26) + tone(note(3, 392.0), 0.2, .triangle, volume: 0.24)
                + sweep(note(0, 392.0), note(-5, 392.0), 0.45, .triangle, volume: 0.22)
        case .Revive:
            return sweep(300.0, 1800.0, 0.35, .noise, volume: 0.12, decay: 1.2) + tone(note(12), 0.2, .sine, volume: 0.2)
        case .Win:
            let melody: [(Int, Double)] = [(0, 0.1), (4, 0.1), (7, 0.1), (12, 0.14), (7, 0.08), (12, 0.36)]
            return mix(Synth.concat(melody.map { tone(note($0.0), $0.1, .triangle, volume: 0.32) }),
                       silence(0.55) + mix(tone(note(0), 0.5, .sine, volume: 0.16), tone(note(7), 0.5, .sine, volume: 0.13)))
        case .Star:
            return tone(1568.0, 0.08, .triangle, volume: 0.26) + tone(2093.0, 0.22, .sine, volume: 0.24)
        case .Tick:
            return tone(940.0, 0.03, .square, volume: 0.1)
        }
    }
}

/// Tile Burst's 17 effects, exactly as the iOS `TileSound`.
enum TileSound {
    typealias Effect = TileSoundEffect
    static let shared = TileSoundBank(gain: 0.55, name: "tile")

    static func play(_ effect: Effect, _ throttleMs: Int64 = 30) { shared.play(effect, throttleMs) }
    static func play(_ effect: Effect, throttleMs: Int64) { shared.play(effect, throttleMs) }
    static func warmUp() {
        shared.warmUp([.Pick, .Place, .Bounce, .Deal, .Clear(0), .Clear(1), .Clear(2), .Multi])
    }
}

// MARK: - ArrowSound

enum ArrowSoundEffect: Hashable {
    case Free(Int)
    case Bump, Heart, Aim, Tap, Hint, Hammer, Win, Lose, Revive, Star

    static func free(step: Int) -> Self { .Free(step) }
    static func free(_ step: Int) -> Self { .Free(step) }
    static let bump = Self.Bump
    static let heart = Self.Heart
    static let aim = Self.Aim
    static let tap = Self.Tap
    static let hint = Self.Hint
    static let hammer = Self.Hammer
    static let win = Self.Win
    static let lose = Self.Lose
    static let revive = Self.Revive
    static let star = Self.Star
}

final class ArrowSoundBank: SoundBank<ArrowSoundEffect> {
    private let scale = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]

    override func synthesize(_ effect: ArrowSoundEffect) -> [Float] {
        switch effect {
        case .Free(let step):
            let degree = min(max(step, 0), scale.count - 1)
            let f = note(scale[degree], 587.33)
            var bell = mix(tone(f, 0.42, .sine, volume: 0.3, decay: 7.0), tone(f * 2, 0.3, .sine, volume: 0.11, decay: 9.0))
            bell = mix(bell, tone(f * 3.01, 0.16, .sine, volume: 0.05, decay: 11.0))
            bell = mix(bell, sweep(f * 0.5, f * 1.5, 0.035, .sine, volume: 0.22, decay: 8.0))
            bell = mix(bell, silence(0.02) + sweep(1400.0, 5200.0, 0.16, .noise, volume: 0.045, decay: 2.6))
            if step >= 3 {
                bell = mix(bell, silence(0.06) + tone(f * 2, 0.12, .triangle, volume: 0.07, decay: 6.0) + tone(f * 2.52, 0.18, .sine, volume: 0.06, decay: 6.0))
            }
            return bell
        case .Bump:
            return mix(sweep(180.0, 90.0, 0.14, .sine, volume: 0.5, decay: 4.0), tone(2600.0, 0.02, .noise, volume: 0.2, decay: 8.0))
        case .Heart:
            return mix(sweep(1800.0, 900.0, 0.12, .triangle, volume: 0.16, decay: 4.0), silence(0.02) + tone(3200.0, 0.06, .noise, volume: 0.1, decay: 5.0))
        case .Aim:
            return tone(1320.0, 0.04, .sine, volume: 0.14, decay: 5.0)
        case .Tap:
            return tone(1700.0, 0.025, .sine, volume: 0.12, decay: 6.0)
        case .Hint:
            return tone(note(7, 784.0), 0.1, .sine, volume: 0.2) + tone(note(12, 784.0), 0.22, .sine, volume: 0.18)
        case .Hammer:
            return mix(mix(sweep(140.0, 60.0, 0.18, .sine, volume: 0.6, decay: 4.0), sweep(5000.0, 1500.0, 0.3, .noise, volume: 0.14, decay: 3.0)),
                       silence(0.05) + Synth.concat([0, 3, 7].map { tone(note($0, 1568.0), 0.04, .triangle, volume: 0.1, decay: 5.0) }))
        case .Win:
            let melody: [(Int, Double)] = [(0, 0.09), (4, 0.09), (7, 0.09), (12, 0.12), (16, 0.34)]
            return mix(Synth.concat(melody.map { tone(note($0.0), $0.1, .triangle, volume: 0.3) }),
                       silence(0.45) + Synth.concat([19, 24, 28].map { tone(note($0, 1046.5), 0.05, .sine, volume: 0.12) }))
        case .Lose:
            return tone(note(7, 392.0), 0.16, .triangle, volume: 0.24) + sweep(note(3, 392.0), note(-5, 392.0), 0.42, .triangle, volume: 0.22)
        case .Revive:
            return sweep(300.0, 1800.0, 0.32, .noise, volume: 0.12, decay: 1.2) + tone(note(12), 0.2, .sine, volume: 0.2)
        case .Star:
            return tone(1568.0, 0.08, .triangle, volume: 0.24) + tone(2093.0, 0.2, .sine, volume: 0.22)
        }
    }
}

/// Arrow Jam's effects, exactly as the iOS `ArrowSound`.
enum ArrowSound {
    typealias Effect = ArrowSoundEffect
    static let shared = ArrowSoundBank(gain: 0.55, name: "arrow")

    static func play(_ effect: Effect, _ throttleMs: Int64 = 30) { shared.play(effect, throttleMs) }
    static func play(_ effect: Effect, throttleMs: Int64) { shared.play(effect, throttleMs) }
    static func warmUp() {
        shared.warmUp((0..<6).map { ArrowSoundEffect.Free($0) } + [.Bump, .Heart, .Aim])
    }
}
