import SwiftUI

/// Zip: one path from 1 through every cell, connecting the numbers in order.
final class ZipModule: GameModule {
    static let shared = ZipModule()

    let pack = LevelPack<ZipLevel>("zip_levels", ZipLevel.parse)

    let info = GameInfo(
        id: "zip",
        name: "Zip",
        tagline: "Draw one path through every cell, connecting the numbers in order.",
        category: "Path",
        colors: [hex(0xFF7A66), hex(0xE772B1), hex(0x9277F5)],
        levelCount: 1500
    )

    var catalog: LevelCatalog { pack }

    let howToPlay = [
        HowToPlayStep(Icons.Rounded.LooksOne, "Start on 1", "Put your finger on dot 1 and drag to draw your path."),
        HowToPlayStep(Icons.Rounded.Route, "Connect in order", "Pass through the numbers in order — 1, 2, 3… — and finish on the last one."),
        HowToPlayStep(Icons.Rounded.GridOn, "Fill every cell", "The path must visit every cell exactly once. It can't cross itself."),
        HowToPlayStep(Icons.Rounded.ViewAgenda, "Mind the walls", "Thick bars are walls. Your path can't pass through them."),
        HowToPlayStep(Icons.Rounded.Undo, "Backtrack anytime", "Drag back over your path, or touch any cell on it, to undo from there."),
    ]

    private let themeLock = NSLock()
    private var cachedMapTheme: LevelMapTheme?

    var mapTheme: LevelMapTheme {
        themeLock.lock()
        defer { themeLock.unlock() }
        if let cachedMapTheme { return cachedMapTheme }
        let theme = LevelMapTheme(
            LevelMapTheme.tiers(
                pack,
                ["First Steps", "Winding Ways", "Switchbacks", "The Labyrinth", "Grand Circuit"],
                [
                    (0x7A2E1E, 0xFF8A5B, 0xFFD0B5), (0x6E1F4A, 0xFF5C93, 0xFFC2D9), (0x4A1F78, 0xB36BFF, 0xE6CCFF),
                    (0x1F2A78, 0x5C7CFF, 0xC6D2FF), (0x2A1236, 0xE0457B, 0xFFD86B),
                ],
                through: 1000
            ) + LevelMapTheme.blocks(
                pack.count, 250,
                ["Long Road", "Night Circuit", "Spiral Steps", "Maze Market", "Knotted Lanes", "Echo Tunnels", "Infinity Loop", "The Last Line"],
                [
                    (0x0F5A52, 0x2FB9A0, 0x9CF0DA), (0x0B0F3A, 0x3A3FA8, 0xFFE38A), (0x5A2A12, 0xD9803A, 0xFFC27A),
                    (0x0F5A46, 0x3FBF8C, 0xC9F5E2), (0x6B2348, 0xFF8A5B, 0xFFD0B5), (0x173D6E, 0x6FC6EA, 0xD9F7FF),
                    (0x150A36, 0x7A23D6, 0xFF4FD8), (0x2A1650, 0xB45CFF, 0xFFD86B),
                ],
                [Motifs.sunset, Motifs.moon, Motifs.waves, Motifs.game, Motifs.tree, Motifs.cloud, Motifs.sparkles, Motifs.crown],
                first: 1001
            )
        )
        cachedMapTheme = theme
        return theme
    }

    func preload() { pack.preload() }

    /// One glowing path spiralling through a 4×4 grid from dot 1 to the last dot.
    @MainActor func BadgeArt(_ size: CGFloat) -> AnyView {
        AnyView(
            Canvas { ctx, canvasSize in
                let n = 4
                let order = [0, 1, 2, 3, 7, 11, 15, 14, 13, 12, 8, 4, 5, 6, 10, 9]
                let cell = min(canvasSize.width, canvasSize.height) / CGFloat(n)
                func center(_ i: Int) -> CGPoint { CGPoint(x: (CGFloat(i % n) + 0.5) * cell, y: (CGFloat(i / n) + 0.5) * cell) }
                var path = Path()
                for (k, i) in order.enumerated() {
                    if k == 0 { path.move(to: center(i)) } else { path.addLine(to: center(i)) }
                }
                ctx.stroke(path, with: .color(Color.white.opacity(0.35)), style: StrokeStyle(lineWidth: cell * 0.5, lineCap: .round, lineJoin: .round))
                ctx.stroke(path, with: .linearGradient(Gradient(colors: [.white, hex(0xFFE2C9)]), startPoint: .zero,
                                                       endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)),
                           style: StrokeStyle(lineWidth: cell * 0.3, lineCap: .round, lineJoin: .round))
                for (i, label) in [(order[0], "1"), (order[order.count - 1], "\(order.count)")] {
                    let c = center(i)
                    let r = cell * 0.34
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(hex(0x3A1F4D)))
                    ctx.draw(Text(label).font(Nunito.font(r * 1.05, FontWeight.Black)).foregroundColor(.white), at: c, anchor: .center)
                }
            }
            .padding(2)
            .frame(width: size, height: size)
        )
    }

    @MainActor func Artwork() -> AnyView { AnyView(LoopingZipDemo()) }

    @MainActor func PlayScreen(_ level: Int) -> AnyView {
        let pack = self.pack
        return AnyView(
            GameShell(
                module: self,
                startLevel: level,
                makeSession: { id, data in ZipGame(pack.level(id) ?? pack.levels[0], data) }
            ) { game in
                ZipBoard(game).padding(.horizontal, 16)
            }
        )
    }
}

/// A small Zip puzzle that solves itself on a loop.
struct LoopingZipDemo: View {
    private static let solution = [0, 1, 2, 3, 4, 9, 8, 7, 6, 5, 10, 15, 20, 21, 16, 11, 12, 13, 14, 19, 18, 17, 22, 23, 24]
    private static let dots = [0, 8, 20, 13, 24]
    private static let walls: [(first: Int, second: Int)] = [(6, 11), (18, 23)]

    // Kotlin's loop: wait 700 ms, add a cell every 130 ms, hold 2 s, start over.
    private static let lead = 0.7
    private static let step = 0.13
    private static let hold = 2.0
    private static var cycle: Double { lead + Double(solution.count - 1) * step + hold }

    @State private var start = Date()

    var body: some View {
        let lab = Lab.colors
        let reduce = Lab.reduceMotion
        TimelineView(.animation(paused: reduce)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let s = Self.solution
                var shown = s.count
                var born: [Int: Double] = [:]
                let nowMs = elapsed * 1000
                if !reduce {
                    let t = elapsed.truncatingRemainder(dividingBy: Self.cycle)
                    let cycleStart = (elapsed - t) * 1000
                    shown = 1
                    if t >= Self.lead {
                        shown = min(s.count, 2 + Int(((t - Self.lead) / Self.step).rounded(.down)))
                    }
                    if shown >= 2 {
                        for count in 2...shown { born[s[count - 1]] = cycleStart + (Self.lead + Double(count - 2) * Self.step) * 1000 }
                    }
                }
                ZipDraw.drawZip(&ctx, lab, 5, 5, Self.dots, Self.walls, Array(s.prefix(shown)), min(size.width, size.height) / 5,
                                isSolved: shown == s.count, now: nowMs, born: born,
                                tile: Color.white.opacity(0.16), wallColor: .white)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
