import SwiftUI
import GameKit

/// A Box Battle level: a square dot grid and a bot strength.
final class BoxLevel: PackLevel {
    let id: Int
    let tier: DifficultyTier
    let rows: Int
    let cols: Int
    let bot: Int

    init(_ id: Int, _ tier: DifficultyTier, _ rows: Int, _ cols: Int, _ bot: Int) {
        self.id = id
        self.tier = tier
        self.rows = rows
        self.cols = cols
        self.bot = bot
    }

    var sizeLabel: String { "\(cols + 1)×\(rows + 1)" }

    static func parse(_ o: JSONObject) -> BoxLevel {
        BoxLevel(o.getInt("id"), DifficultyTier.parse(o.getString("tier")), o.getInt("rows"), o.getInt("cols"), o.optInt("bot", 1))
    }
}

/// Box Battle: Dots & Boxes against a bot. Draw lines, close boxes, out-score your rival.
final class BoxBattleModule: GameModule {
    static let shared = BoxBattleModule()

    let pack = LevelPack<BoxLevel>("boxbattle_levels", BoxLevel.parse)

    let info = GameInfo(
        id: "boxbattle",
        name: "Box Battle",
        tagline: "Draw lines, close boxes and out-smart your rival across 3,000 levels.",
        category: "Strategy",
        colors: [hex(0xF5B91E), hex(0x8A4FE8)],
        levelCount: 3000
    )

    var catalog: LevelCatalog { pack }

    let howToPlay = [
        HowToPlayStep(Icons.Rounded.Gesture, "Draw a line", "Drag between two neighbouring dots to draw a line. You and the rival take turns."),
        HowToPlayStep(Icons.Rounded.CheckBox, "Close a box", "Draw the fourth side of a box to claim it in your colour."),
        HowToPlayStep(Icons.Rounded.Bolt, "Go again", "Every box you close earns another turn — chain boxes for a big combo."),
        HowToPlayStep(Icons.Rounded.EmojiEvents, "Win the board", "When the grid is full, whoever owns the most boxes wins the level."),
    ]

    lazy var mapTheme: LevelMapTheme = LevelMapTheme(
        LevelMapTheme.blocks(
            pack.count, 500,
            ["Rookie Ring", "Sunny Street", "Combo Court", "Chain Master", "Grand Arena", "Champion's Crown"],
            [
                (0x15A088, 0x0B5247, 0x5BE6CB),
                (0xF0B31E, 0x8A6207, 0xFFE27A),
                (0xF0730F, 0x8A3B07, 0xFFC27A),
                (0x8A4FE8, 0x45228C, 0xC9A6FF),
                (0x4A4D5A, 0x22242B, 0xD3D5DE),
                (0xC98A0B, 0x5A3A05, 0xFFD86B),
            ],
            [Motifs.game, Motifs.sun, Motifs.sparkles, Motifs.flame, Motifs.bolt, Motifs.crown]
        )
    )

    private init() {}

    func preload() { pack.preload() }

    @MainActor func BadgeArt(_ size: CGFloat) -> AnyView { AnyView(BoxBattleBadge(size: size)) }

    @MainActor func Artwork() -> AnyView { AnyView(BoxBattleArtwork()) }

    @MainActor func PlayScreen(_ level: Int) -> AnyView { AnyView(BoxBattlePlay(level)) }
}

private func boxRect(_ g: BoardGeom, _ r: Int, _ c: Int) -> CGRect {
    let tl = g.dot(r, c)
    let pad = g.cell * 0.22
    return CGRect(x: tl.x + pad, y: tl.y + pad, width: g.cell - 2 * pad, height: g.cell - 2 * pad)
}

/// The badge: a 2×2 board with one captured box.
private struct BoxBattleBadge: View {
    let size: CGFloat

    var body: some View {
        let size = size
        Canvas { ctx, s in
            let g = BoardGeom.of(s.width, s.height, 2, 2)
            let m = g.m
            ctx.boardCard(CGRect(origin: .zero, size: s), g.side * 0.12)
            ctx.crayon(scribblePath(boxRect(g, 0, 0), 11), BoxArt.crayon(.You), m.crayonW * 1.3, 1)
            for (a, b) in [(0, 1), (0, 3), (3, 4), (1, 4)] { ctx.boneLine(g.dot(a), g.dot(b), m.endW, m.midW, BoxArt.you) }
            ctx.boneLine(g.dot(4), g.dot(5), m.endW, m.midW, BoxArt.rival)
            ctx.boneLine(g.dot(7), g.dot(8), m.endW, m.midW, BoxArt.rival)
            for i in 0..<9 { ctx.flatDot(g.dot(i), m.dotR) }
        }
        .frame(width: size, height: size)
    }
}

/// A looping 2×2 showcase in the reference's style: pencils draw lines, a box is captured.
struct BoxBattleArtwork: View {
    @State private var start = Date()

    var body: some View {
        let reduce = Lab.reduceMotion
        ZStack {
            // Backdrop and board card never move: one static layer.
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Self.backdrop, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                let side = min(size.width, size.height) * 0.86
                var c = ctx
                c.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
                c.boardCard(CGRect(x: 0, y: 0, width: side, height: side), side * 0.1)
            }
            TimelineView(.animation(minimumInterval: nil, paused: reduce)) { timeline in
                let time: Float = reduce ? 4 : Float(timeline.date.timeIntervalSince(start))
                Canvas { ctx, size in
                    _ = time
                    let side = min(size.width, size.height) * 0.86
                    var c = ctx
                    c.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
                    Self.drawFrame(c, side, time)
                }
            }
        }
        .onAppear { start = Date() }
    }

    private static let backdrop = Gradient(colors: [hex(0x2E2F38), hex(0x15161B)])

    // (from dot, to dot, owner, start second)
    private static let moves: [(Int, Int, Player, Float)] = [
        (0, 1, .You, 0.2), (4, 5, .Rival, 0.75), (0, 3, .You, 1.3), (1, 4, .Rival, 1.85), (3, 4, .You, 2.4),
    ]

    private static func drawFrame(_ ctx: GraphicsContext, _ side: CGFloat, _ time: Float) {
        let g = BoardGeom.of(side, side, 2, 2)
        let m = g.m
        let t = time.truncatingRemainder(dividingBy: 4.6)
        let capture = t - 2.7
        let scribble = min(max((capture - BoxFx.SCRIBBLE_AT) / BoxFx.SCRIBBLE_FOR, 0), 1)
        let tip = capture > 0 ? ctx.crayon(scribblePath(boxRect(g, 0, 0), 11), BoxArt.crayon(.You), m.crayonW, CGFloat(scribble)) : nil
        var pen: (CGPoint, Player)?
        // Settled and springing lines share one blurred glow layer.
        var bones: [(CGPoint, CGPoint, CGFloat, CGFloat, Player)] = []
        for (from, to, owner, at) in moves {
            let e = t - at
            if e <= 0 { continue }
            let a = g.dot(from)
            let b = g.dot(to)
            let grow = min(max(e / 0.32, 0), 1)
            if grow < 1 {
                let head = CGPoint(x: a.x + (b.x - a.x) * CGFloat(grow), y: a.y + (b.y - a.y) * CGFloat(grow))
                ctx.growLine(a, head, m.growW, BoxArt.line(owner))
                pen = (head, owner)
            } else {
                let s = CGFloat(springStep(e - 0.32, 0.36, 0.32))
                bones.append((a, b, m.growW + (m.endW - m.growW) * s, m.growW + (m.midW - m.growW) * s, owner))
            }
        }
        if !bones.isEmpty {
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: boxBlurSigma(max(m.endW * 1.45 * 0.32, 0.5))))
                for (a, b, endW, _, owner) in bones {
                    var p = Path()
                    p.move(to: a)
                    p.addLine(to: b)
                    l.stroke(p, with: .color(BoxArt.line(owner).opacity(0.75)), style: StrokeStyle(lineWidth: endW * 1.45, lineCap: .round, lineJoin: .round))
                }
            }
            for (a, b, endW, midW, owner) in bones { ctx.boneLine(a, b, endW, midW, BoxArt.line(owner), halo: false) }
        }
        if capture > 0 && capture < BoxFx.GOLD_AT + 0.35 {
            let fade: Float = capture < BoxFx.GOLD_AT ? 1 : 1 - (capture - BoxFx.GOLD_AT) / 0.35
            ctx.glowTrace(g.dot(0), g.cell, BoxArt.glow(.You), m.growW * 0.7, CGFloat(scribble), CGFloat(fade))
        }
        let goldE = capture - BoxFx.GOLD_AT
        let gold: Float = (goldE >= 0 && goldE <= BoxFx.GOLD_FOR) ? (goldE < 0.1 ? goldE / 0.1 : 1 - (goldE - 0.1) / (BoxFx.GOLD_FOR - 0.1)) : 0
        for i in 0..<9 {
            let corner = i == 0 || i == 1 || i == 3 || i == 4
            ctx.flatDot(g.dot(i), m.dotR * (1 + (corner ? 0.34 * CGFloat(gold) : 0)), corner ? CGFloat(gold) : 0)
        }
        if let (p, owner) = pen { ctx.pencil(p, m.pencilLen, owner) }
        if let tip, scribble >= 0.001 && scribble <= 0.999 { ctx.pencil(tip, m.pencilLen * 0.85, .You) }
    }
}
