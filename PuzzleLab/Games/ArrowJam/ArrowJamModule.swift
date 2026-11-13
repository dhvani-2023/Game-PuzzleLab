import SwiftUI

/// Arrow Jam: tap the arrows free in the right order and reveal the picture.
final class ArrowJamModule: GameModule {
    static let shared = ArrowJamModule()

    let pack = ArrowLevelPack("arrowjam_levels")
    let dailyPack = ArrowLevelPack("arrowjam_daily")

    let info = GameInfo(
        id: "arrowjam",
        name: "Arrow Jam",
        tagline: "Tap the arrows free in the right order and reveal the picture. 3,000 levels.",
        category: "Logic",
        colors: [hex(0xF2B23C), hex(0xD9762A)],
        levelCount: 3000
    )

    var catalog: LevelCatalog { pack }

    let howToPlay = [
        HowToPlayStep(Icons.Rounded.TouchApp, "Tap to free", "Tap an arrow and it slides out along its own path, the way its head points."),
        HowToPlayStep(Icons.Rounded.Favorite, "Mind the way", "If another arrow is in the way, it bumps back and you lose a heart. You have three per level."),
        HowToPlayStep(Icons.Rounded.PanTool, "Hold to aim", "Hold an arrow to preview its lane: green means clear, red means blocked. Release to fire, slide away to cancel."),
        HowToPlayStep(Icons.Rounded.OpenInFull, "Zoom in", "Pinch to zoom and drag to look around big pictures. Hints and the hammer help when you're stuck."),
    ]

    private let themeLock = NSLock()
    private var cachedMapTheme: LevelMapTheme?

    var mapTheme: LevelMapTheme {
        themeLock.lock()
        defer { themeLock.unlock() }
        if let cachedMapTheme { return cachedMapTheme }
        let theme = LevelMapTheme(
            LevelMapTheme.blocks(
                pack.count, 100,
                ["Paper Meadow", "Ink Harbour", "Mint Grove", "Sunset Kites", "Copper Canyon", "Arctic Lines", "Neon Alley", "Ember Forge", "Starlit Maze", "The Grand Knot"],
                [
                    (0x6B4E2A, 0xD9B77A, 0xFFE3A3), (0x1C2A5A, 0x4F7BD9, 0xA9C8FF), (0x0F5A46, 0x3FBF8C, 0xC9F5E2),
                    (0x6B2348, 0xFF8A5B, 0xFFD0B5), (0x5A2A12, 0xD9803A, 0xFFC27A), (0x173D6E, 0x6FC6EA, 0xD9F7FF),
                    (0x150A36, 0x7A23D6, 0xFF4FD8), (0x2E0A18, 0xD6402B, 0xFF9A5A), (0x0B0F3A, 0x3A3FA8, 0xFFE38A),
                    (0x2A1650, 0xB45CFF, 0xFFD86B),
                ],
                [Motifs.leaf, Motifs.boat, Motifs.tree, Motifs.sunset, Motifs.mountain, Motifs.snow, Motifs.bolt, Motifs.flame, Motifs.sparkles, Motifs.crown]
            ),
            coins: {
                ArrowBank.load()
                return ArrowBank.coins
            }
        )
        cachedMapTheme = theme
        return theme
    }

    var daily: DailyChallenge? {
        let id = ArrowRecords.dailyLevelID(dailyPack.count)
        let arrows = dailyPack.level(id)?.a.count ?? 0
        return DailyChallenge("Arrow Jam Daily", "Free today's picture: \(arrows) arrows", ArrowRecords.dailyStreak, ArrowRecords.isDailyDone)
    }

    func preload() {
        pack.preload()
        dailyPack.preload()
    }

    /// A glossy three-colour arrow snake.
    @MainActor func BadgeArt(_ size: CGFloat) -> AnyView {
        AnyView(
            Canvas { ctx, canvasSize in
                let cell = canvasSize.width / 5
                let snakes: [([(Int, Int)], ArrowRGBA)] = [
                    ([(4, 0), (3, 0), (3, 1), (2, 1), (1, 1), (0, 1)], .white),
                    ([(4, 2), (4, 3), (3, 3), (2, 3), (2, 2), (1, 2)], ArrowRGBA(0x4A2370)),
                    ([(0, 3), (0, 4), (1, 4), (2, 4), (3, 4)], ArrowRGBA(0xE8455B)),
                ]
                for (i, snake) in snakes.enumerated() {
                    let piece = ArrowPiece.of(i, snake.0)
                    let points = ArrowGeometry.body(piece, 0).map { CGPoint(x: $0.x * cell, y: $0.y * cell) }
                    let dir = ArrowGeometry.direction(points, piece.heading)
                    var shadow = ctx
                    shadow.translateBy(x: 0, y: cell * 0.08)
                    ArrowArt.drawArrow(&shadow, points, dir, cell, ArrowArt.Style(ArrowRGBA.black.copy(alpha: 0.22), cell * 0.36, 0))
                    ArrowArt.drawArrow(&ctx, points, dir, cell, ArrowArt.Style(snake.1, cell * 0.36, 0.35))
                }
            }
            .padding(size * 0.06)
            .frame(width: size, height: size)
        )
    }

    @MainActor func Artwork() -> AnyView {
        AnyView(ArrowJamArtwork().clipShape(RoundedRectangle(cornerRadius: 26, style: .circular)))
    }

    @MainActor func PlayScreen(_ level: Int) -> AnyView { AnyView(ArrowJamPlay(level, .Adventure)) }

    @MainActor func DailyScreen() -> AnyView { AnyView(ArrowJamPlay(ArrowRecords.dailyLevelID(dailyPack.count), .Daily)) }
}

private let artPieces: [ArrowPiece] = [
    [(0, 1), (0, 2), (0, 3), (0, 4), (0, 5)], [(5, 0), (4, 0), (3, 0), (2, 0), (1, 0)], [(2, 2), (1, 2), (1, 3), (1, 4)],
    [(4, 5), (3, 5), (2, 5), (1, 5)], [(3, 1), (2, 1), (1, 1)], [(5, 1), (5, 2), (5, 3), (5, 4), (5, 5)],
    [(3, 2), (3, 3), (3, 4), (4, 4)], [(4, 1), (4, 2), (4, 3)], [(2, 3), (2, 4)],
].enumerated().map { ArrowPiece.of($0.offset, $0.element) }

/// A live 6×6 board on frosted glass: arrows fly in, slide out one by one, one bumps red.
struct ArrowJamArtwork: View {
    @State private var start = Date()

    private static let order = [0, 1, 3, 2]
    private static let bumper = 7
    private static let palette = [0x4A2370, 0xE8455B, 0x1F7A6E, 0x2F4FB0, 0xB0362F, 0x4A2370, 0x1F7A6E, 0x2F4FB0, 0xE8455B].map { ArrowRGBA(UInt32($0)) }

    var body: some View {
        let reduce = Lab.reduceMotion
        TimelineView(.animation(paused: reduce)) { timeline in
            let time = reduce ? 0.3 : timeline.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let cell = min(size.width, size.height) / 8
                let origin = CGPoint(x: (size.width - cell * 6) / 2, y: (size.height - cell * 6) / 2)
                let width = cell * 0.27
                let dot = ArrowRGBA(0x7A4310, 0.25).color
                for r in 0..<6 {
                    for c in 0..<6 {
                        let p = CGPoint(x: origin.x + (CGFloat(c) + 0.5) * cell, y: origin.y + (CGFloat(r) + 0.5) * cell)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)), with: .color(dot))
                    }
                }
                let step = 0.75
                let intro = 1.6
                let fadeAt = intro + Double(Self.order.count) * step + 0.7
                let cycle = fadeAt + 0.3
                let t = time.truncatingRemainder(dividingBy: cycle)
                for piece in artPieces {
                    let leaveIndex = Self.order.firstIndex(of: piece.id)
                    let leaveAt = leaveIndex.map { intro + Double($0) * step } ?? Double.greatestFiniteMagnitude
                    var color = Self.palette[piece.id % Self.palette.count]
                    var glow: ArrowRGBA?
                    let enter = min(max((t - Double(piece.id) * 0.04) / 0.45, 0), 1)
                    let settle = 1 - pow(2.0, -9 * enter) * cos(enter * 10.5)
                    var slide = -(1 - settle) * 2.5
                    var opacity = min(1.0, enter * 2.5)
                    if t > leaveAt {
                        let p = min(1.0, (t - leaveAt) / 0.48)
                        slide = p * p * 9
                        opacity = 1 - max(0.0, p - 0.55) / 0.45
                        glow = .white
                    }
                    if t > fadeAt { opacity = min(opacity, 1 - (t - fadeAt) / 0.3) }
                    if piece.id == Self.bumper && t > intro + 0.95 && t < intro + 1.4 {
                        let p = (t - intro - 0.95) / 0.45
                        slide = sin(p * Double.pi) * 0.55
                        color = ArrowTheme.crash
                        glow = ArrowTheme.crash
                    }
                    if opacity <= 0.01 { continue }
                    let points = ArrowGeometry.body(piece, slide).map { CGPoint(x: origin.x + $0.x * cell, y: origin.y + $0.y * cell) }
                    let dir = ArrowGeometry.direction(points, piece.heading)
                    var shadow = ctx
                    shadow.translateBy(x: 0, y: 1.2)
                    ArrowArt.drawArrow(&shadow, points, dir, cell, ArrowArt.Style(ArrowRGBA(0x5A2A00, 0.28 * CGFloat(opacity)), width, 0))
                    ArrowArt.drawArrow(&ctx, points, dir, cell, ArrowArt.Style(color, width, 0.3, glow, cell * 0.35, CGFloat(opacity)))
                }
            }
        }
        .background(LinearGradient(stops: [.init(color: Color.white.opacity(0.35), location: 0), .init(color: .clear, location: 0.5)],
                                   startPoint: .top, endPoint: .bottom))
        .background(LinearGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
