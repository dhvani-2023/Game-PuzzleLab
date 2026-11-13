import SwiftUI
import GameKit

/// Patches: split the grid into rectangles, one per clue.
final class PatchesModule: GameModule {
    static let shared = PatchesModule()

    let pack = LevelPack<PatchesLevel>("patches_levels", PatchesLevel.parse)

    let info = GameInfo(
        id: "patches",
        name: "Patches",
        tagline: "Fill the grid with rectangles. Every clue tells you its patch size — no gaps, no overlaps.",
        category: "Logic",
        colors: [hex(0x2FB9A0), hex(0x3D8BFF)],
        levelCount: 3000
    )

    var catalog: LevelCatalog { pack }

    let howToPlay = [
        HowToPlayStep(Icons.Rounded.GridOn, "Fill every cell", "Cover the whole grid with rectangles. No gaps and no overlaps."),
        HowToPlayStep(Icons.Rounded.Tag, "One clue per patch", "Each patch holds exactly one clue, and its number is how many cells the patch covers."),
        HowToPlayStep(Icons.Rounded.CropPortrait, "Shape clues", "A square, wide or tall badge means the patch must be that shape. Badges without a number can be any size."),
        HowToPlayStep(Icons.Rounded.Draw, "Drag to draw", "Drag across cells to draw a patch. Tap a patch to remove it, or redraw over it."),
    ]

    lazy var mapTheme: LevelMapTheme = LevelMapTheme(
        LevelMapTheme.tiers(
            pack,
            ["Garden Grid", "Quilt Market", "Patchwork Hills", "Tailor's Tower", "Master Loom"],
            [
                (0x0F5A52, 0x2FB9A0, 0x9CF0DA), (0x123E7A, 0x3D8BFF, 0xA9CCFF), (0x4A2378, 0x9B6BFF, 0xD8C6FF),
                (0x6B1F45, 0xE0567F, 0xFFB8CB), (0x2A1650, 0x5B47F5, 0xFFD86B),
            ],
            through: 1000
        ) + LevelMapTheme.blocks(
            pack.count, 250,
            ["Velvet Vale", "Button Bay", "Quilted Peaks", "Silk Road", "Tapestry Hall", "Golden Thread", "Loom of Legends", "Grand Quilt"],
            [
                (0x5A2A12, 0xD9803A, 0xFFC27A), (0x0F5A46, 0x3FBF8C, 0xC9F5E2), (0x173D6E, 0x6FC6EA, 0xD9F7FF),
                (0x6B2348, 0xFF8A5B, 0xFFD0B5), (0x2E0A18, 0xD6402B, 0xFF9A5A), (0x6B4E2A, 0xD9B77A, 0xFFE3A3),
                (0x150A36, 0x7A23D6, 0xFF4FD8), (0x2A1650, 0xB45CFF, 0xFFD86B),
            ],
            [Motifs.leaf, Motifs.boat, Motifs.mountain, Motifs.sunset, Motifs.flame, Motifs.sun, Motifs.sparkles, Motifs.crown],
            first: 1001
        )
    )

    private init() {}

    func preload() { pack.preload() }

    @MainActor func BadgeArt(_ size: CGFloat) -> AnyView {
        AnyView(PinwheelLogo(size * 0.82).frame(width: size, height: size))
    }

    @MainActor func Artwork() -> AnyView {
        AnyView(LoopingDemoBoard(DemoBoards.medium, tile: Color.white.opacity(0.16), stepMs: 350))
    }

    @MainActor func PlayScreen(_ level: Int) -> AnyView {
        let pack = pack
        return AnyView(
            GameShell(module: self, startLevel: level, makeSession: { id, data in PatchesGame(pack.level(id) ?? pack.levels[0], data) }) { game in
                PatchesPlayArea(game)
            }
        )
    }
}

/// One solved patch in a decorative demo board.
final class DemoPiece {
    let rect: GridRect
    let color: Int
    let clue: Cell

    init(_ rect: GridRect, _ color: Int, _ clue: Cell) {
        self.rect = rect
        self.color = color
        self.clue = clue
    }
}

final class DemoBoardSpec {
    let rows: Int
    let cols: Int
    let pieces: [DemoPiece]

    init(_ rows: Int, _ cols: Int, _ pieces: [DemoPiece]) {
        self.rows = rows
        self.cols = cols
        self.pieces = pieces
    }
}

enum DemoBoards {
    private static func p(_ r: Int, _ c: Int, _ h: Int, _ w: Int, _ color: Int, _ clue: (Int, Int)) -> DemoPiece {
        DemoPiece(GridRect(r, c, h, w), color, Cell(clue.0, clue.1))
    }

    static let small = DemoBoardSpec(4, 4, [
        p(0, 0, 1, 3, 0, (0, 1)), p(1, 0, 2, 2, 5, (2, 0)), p(1, 2, 2, 1, 3, (1, 2)), p(0, 3, 3, 1, 2, (1, 3)), p(3, 0, 1, 4, 6, (3, 2)),
    ])

    static let medium = DemoBoardSpec(5, 5, [
        p(0, 0, 2, 2, 0, (1, 0)), p(0, 2, 1, 3, 2, (0, 3)), p(1, 2, 2, 1, 5, (2, 2)), p(1, 3, 2, 2, 3, (1, 4)),
        p(2, 0, 3, 1, 6, (3, 0)), p(2, 1, 2, 1, 1, (2, 1)), p(3, 2, 1, 3, 7, (3, 3)), p(4, 1, 1, 4, 4, (4, 2)),
    ])
}

/// Demo board that fills itself piece by piece, pauses, then starts over.
struct LoopingDemoBoard: View {
    let spec: DemoBoardSpec
    var tile: Color? = nil
    var stepMs: Int = 500
    var showClues: Bool = true

    init(_ spec: DemoBoardSpec, tile: Color? = nil, stepMs: Int = 500, showClues: Bool = true) {
        self.spec = spec
        self.tile = tile
        self.stepMs = stepMs
        self.showClues = showClues
    }

    @State private var shown = 0

    var body: some View {
        let reduce = Lab.reduceMotion
        DemoBoard(spec, shown, tile: tile, showClues: showClues)
            .task(id: reduce) {
                if reduce { shown = spec.pieces.count; return }
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .milliseconds(600))
                        for i in 1...spec.pieces.count {
                            shown = i
                            try await Task.sleep(for: .milliseconds(stepMs))
                        }
                        try await Task.sleep(for: .milliseconds(1600))
                    } catch { return }
                    shown = 0
                }
            }
    }
}

/// Static rendering of a demo board with the first `shown` pieces filled in.
struct DemoBoard: View {
    let spec: DemoBoardSpec
    let shown: Int
    var tile: Color? = nil
    var showClues: Bool = true

    init(_ spec: DemoBoardSpec, _ shown: Int, tile: Color? = nil, showClues: Bool = true) {
        self.spec = spec
        self.shown = shown
        self.tile = tile
        self.showClues = showClues
    }

    var body: some View {
        let lab = Lab.colors
        let tileColor = tile ?? lab.surfaceAlt
        let spec = spec
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(spec.cols), geo.size.height / CGFloat(spec.rows))
            let boardH = cell * CGFloat(spec.rows)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let inset = cell * 0.06
                    for i in 0..<(spec.rows * spec.cols) {
                        ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i % spec.cols) * cell + inset, y: CGFloat(i / spec.cols) * cell + inset,
                                                          width: cell - inset * 2, height: cell - inset * 2), cornerRadius: cell * 0.2),
                                 with: .color(tileColor))
                    }
                }
                ForEach(Array(spec.pieces.enumerated()), id: \.offset) { index, piece in
                    DemoPieceView(piece: piece, on: index < shown, cell: cell, boardH: boardH, color: lab.patch(piece.color))
                }
                if showClues {
                    ForEach(Array(spec.pieces.enumerated()), id: \.offset) { index, piece in
                        ClueBadge(PatchesClue(piece.clue.row, piece.clue.col, piece.rect.area, nil, piece.color),
                                  index < shown ? .Satisfied : .Open, cell, lab.patch(piece.color))
                            .frame(width: cell, height: cell)
                            .offset(x: cell * CGFloat(piece.clue.col), y: cell * CGFloat(piece.clue.row))
                    }
                }
            }
        }
        .aspectRatio(CGFloat(spec.cols) / CGFloat(spec.rows), contentMode: .fit)
    }
}

/// A demo piece popping in (scale 0.5 → 1 from its centre) and out.
private struct DemoPieceView: View {
    let piece: DemoPiece
    let on: Bool
    let cell: CGFloat
    let boardH: CGFloat
    let color: Color

    var body: some View {
        let c = cell
        let inset = c * 0.06
        let m = PatchTileMargin.value
        let rect = piece.rect
        let left = CGFloat(rect.col) * c + inset
        let top = CGFloat(rect.row) * c + inset
        let width = CGFloat(rect.width) * c - inset * 2
        let height = CGFloat(rect.height) * c - inset * 2
        let color = color
        let boardH = boardH
        Canvas { ctx, _ in
            drawPatchTile(ctx, CGRect(x: m, y: m, width: width, height: height), color, true, c * 0.22, .red,
                          from: m - top, to: m - top + boardH)
        }
        .frame(width: width + m * 2, height: height + m * 2)
        .scaleEffect(on ? 1 : 0.5)
        .opacity(on ? 1 : 0)
        .animation(labSpring(0.45, 0.62), value: on)
        .offset(x: left - m, y: top - m)
        .allowsHitTesting(false)
    }
}
