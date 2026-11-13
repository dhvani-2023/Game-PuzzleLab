import SwiftUI
import GameKit

/** Tile Burst: drop blocks, clear lines, chain combos. Classic, Daily and 3,000 Adventure levels. */
final class TileBurstModule: GameModule {
    static let shared = TileBurstModule()

    let pack = LevelPack<TileLevel>("tileburst_levels", TileLevel.parse)
    static var pack: LevelPack<TileLevel> { shared.pack }

    let info = GameInfo(
        id: "tileburst",
        name: "Tile Burst",
        tagline: "Drop blocks, clear lines and chain huge combos. Classic, Daily and 3,000 levels.",
        category: "Puzzle",
        colors: [hex(0x4B5CF0), hex(0xA45CF0)],
        levelCount: 3000
    )
    static var info: GameInfo { shared.info }

    var catalog: LevelCatalog { pack }

    let howToPlay: [HowToPlayStep] = [
        HowToPlayStep(Icons.Rounded.Draw, "Drag and drop", "Drag a piece from the tray onto the board. Pieces don't rotate, and new ones arrive once all three are placed."),
        HowToPlayStep(Icons.Rounded.Reorder, "Clear lines", "Fill a whole row or column to clear it. Clear several at once for big points."),
        HowToPlayStep(Icons.Rounded.Bolt, "Chain combos", "Clear lines on back-to-back moves to build a combo. It survives two misses. At ×8 you hit Fever: double points!"),
        HowToPlayStep(Icons.Rounded.Diamond, "Adventure goals", "In Adventure, clear lines holding gems to collect them, or clear the starting picture. Finish in fewer trays for 3 stars."),
    ]

    lazy var mapTheme: LevelMapTheme = LevelMapTheme(
        LevelMapTheme.blocks(
            pack.count, 100, TileArt.worlds.map(\.name),
            TileArt.worlds.map { ($0.top, $0.bottom, $0.accent) },
            [Motifs.moon, Motifs.waves, Motifs.sunset, Motifs.leaf, Motifs.cloud, Motifs.sun, Motifs.snow, Motifs.flame, Motifs.game, Motifs.sparkles]
        ),
        coins: { TileBank.load(); return TileBank.coins }
    )

    var daily: DailyChallenge? {
        let day = TileRecords.day()
        return DailyChallenge("Tile Burst Daily", "Score \(tileGrouped(TileRecords.dailyTarget(day))) on today's board",
                              TileRecords.dailyStreak, TileRecords.isDailyDone(day))
    }

    func preload() { pack.preload() }

    /** A T piece landing on a full row of painted blocks. */
    @MainActor func BadgeArt(_ size: CGFloat) -> AnyView { AnyView(TileBadgeArt(size: size)) }

    @MainActor func Artwork() -> AnyView { AnyView(TileBurstArtwork()) }

    @MainActor func PlayScreen(_ level: Int) -> AnyView { AnyView(TileBurstPlay(level, .Adventure)) }

    @MainActor func DailyScreen() -> AnyView { AnyView(TileBurstPlay(1, .Daily)) }
}

private struct TileBadgeArt: View {
    let size: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        Canvas { ctx, sz in
            let s = scale
            let cell = min(sz.width, sz.height) * s / 3
            let px = Kt.roundToInt(Double(cell))
            for (r, line) in [".4.", "444", "220"].enumerated() {
                for (c, ch) in line.enumerated() {
                    guard let tone = ch.wholeNumberValue else { continue }
                    let x = CGFloat(Kt.roundToInt(Double(CGFloat(c) * cell))) / s
                    let y = CGFloat(Kt.roundToInt(Double(CGFloat(r) * cell))) / s
                    ctx.draw(TileArt.block(tone, px).image(scale: s), in: CGRect(x: x, y: y, width: CGFloat(px) / s, height: CGFloat(px) / s))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/** A tiny live board: a piece drops in, completes a row, and the row bursts. */
struct TileBurstArtwork: View {
    var compact: Bool = false
    @Environment(\.displayScale) private var scale
    @State private var start = Date()

    init(compact: Bool = false) { self.compact = compact }

    private static let layout = ["......", "....5.", "2...55", "22.666", "33..44", "113344"]

    var body: some View {
        let reduce = Lab.reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: reduce)) { timeline in
            let time = reduce ? 0 : CGFloat(timeline.date.timeIntervalSince(start))
            Canvas { ctx, size in
                draw(ctx, size, time)
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ time: CGFloat) {
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [hex(0x2E2A8C), hex(0x6A4FE0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let n: CGFloat = 6
        let cell = min((size.width - 18) / n, (size.height - 18) / n)
        if cell <= 1 { return }
        let side = cell * n
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        ctx.fill(Path(roundedRect: CGRect(x: origin.x - 5, y: origin.y - 5, width: side + 10, height: side + 10), cornerRadius: 12), with: .color(hex(0x8E7CFF, 0.8)))
        ctx.fill(Path(roundedRect: CGRect(x: origin.x - 2, y: origin.y - 2, width: side + 4, height: side + 4), cornerRadius: 10), with: .color(hex(0x17134A)))
        for r in 0..<6 {
            for c in 0..<6 {
                let rect = CGRect(x: origin.x + CGFloat(c) * cell + 1.5, y: origin.y + CGFloat(r) * cell + 1.5, width: cell - 3, height: cell - 3)
                ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.16), with: .color(hex((r + c) % 2 == 0 ? 0x252070 : 0x221D68)))
            }
        }
        let phase = (time / 2.6).truncatingRemainder(dividingBy: 1)
        let row = 4
        let clearing = phase > 0.42 && phase < 0.62
        let cleared = phase >= 0.62 && phase < 0.9
        let s = scale
        let px = max(1, Kt.roundToInt(Double(cell * s)))
        func block(_ tone: Int, _ r: CGFloat, _ c: CGFloat, _ scaleBy: CGFloat = 1, _ alpha: CGFloat = 1) {
            let sz = cell * scaleBy
            let rect = CGRect(x: origin.x + (c + 0.5) * cell - sz / 2, y: origin.y + (r + 0.5) * cell - sz / 2, width: sz, height: sz)
            var g = ctx
            g.opacity = Double(min(max(alpha, 0), 1))
            g.draw(TileArt.block(tone, px).image(scale: s), in: rect)
        }
        for (r, line) in TileBurstArtwork.layout.enumerated() {
            for (c, ch) in line.enumerated() {
                guard let tone = ch.wholeNumberValue else { continue }
                if r == row && (clearing || cleared) {
                    if clearing {
                        let t = (phase - 0.42) / 0.2
                        block(6, CGFloat(r), CGFloat(c), 1 + t * 0.25, 1 - t)
                    }
                    continue
                }
                block(tone, CGFloat(r), CGFloat(c))
            }
        }
        if phase < 0.42 || phase >= 0.9 {
            let t: CGFloat = phase >= 0.9 ? 0 : min(1, phase / 0.32)
            let e = 1 - (1 - t) * (1 - t) * (1 - t)
            let y = -1.4 + (CGFloat(row) + 1.4) * e
            for dc in 0..<2 { block(6, y, CGFloat(2 + dc), 1, phase >= 0.9 ? (phase - 0.9) / 0.1 : 1) }
        }
        if clearing {
            let t = (phase - 0.42) / 0.2
            ctx.fill(Path(roundedRect: CGRect(x: origin.x - 6, y: origin.y + CGFloat(row) * cell + cell * 0.2, width: side + 12, height: cell * 0.6), cornerRadius: cell * 0.3),
                     with: .color(Color.white.opacity(Double(0.85 * (1 - t)))))
        }
        if !compact && phase > 0.45 && phase < 0.8 {
            let t = (phase - 0.45) / 0.35
            let a: CGFloat = t < 0.8 ? 1 : (1 - t) * 5
            var g = ctx
            g.opacity = Double(min(max(a, 0), 1))
            let text = g.resolve(Text("Combo ×3").font(Nunito.font(cell * 0.7, .black)).foregroundColor(hex(0xFFD35A)))
            g.draw(text, at: CGPoint(x: size.width / 2, y: origin.y + CGFloat(row) * cell - t * cell), anchor: .center)
        }
    }
}
