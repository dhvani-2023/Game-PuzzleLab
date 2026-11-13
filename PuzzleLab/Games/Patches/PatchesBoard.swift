import SwiftUI
import GameKit

/// SwiftUI's `color.gradient`: a little lighter at the top, a little deeper at the bottom (cached, so
/// animating tiles never redo the colour maths).
@MainActor
private var softGradients: [Color: [Double: Gradient]] = [:]

extension Color {
    /// Kotlin `Color.softGradient(alpha)`: the stops of the vertical brush.
    @MainActor
    func softGradient(_ alpha: Double = 1) -> Gradient {
        if let g = softGradients[self]?[alpha] { return g }
        let g = Gradient(colors: [mix(.white, 0.14).copy(alpha: alpha), mix(.black, 0.06).copy(alpha: alpha)])
        softGradients[self, default: [:]][alpha] = g
        return g
    }
}

/// Interactive Patches board. Drag across cells to draw a patch; tap a patch to remove it.
struct PatchesBoard: View {
    let game: PatchesGame

    init(_ game: PatchesGame) { self.game = game }

    @State private var dragStart: Cell?
    @State private var dragCurrent: Cell?
    @State private var dragMoved = false
    /// True while a finger is down; resets by itself if the system cancels the touch.
    @GestureState private var touching = false

    var body: some View {
        let lab = Lab.colors
        let rows = game.rows
        let cols = game.cols
        GeometryReader { geo in
            let pad: CGFloat = 8
            let cell = max(1, floor(min((geo.size.width - pad * 2) / CGFloat(cols), (geo.size.height - pad * 2) / CGFloat(rows))))
            let boardW = cell * CGFloat(cols)
            let boardH = cell * CGFloat(rows)
            let corner = cell * 0.42
            let shape = RoundedRectangle(cornerRadius: corner, style: .circular)
            ZStack(alignment: .topLeading) {
                // Wells
                Canvas { ctx, _ in
                    let inset = cell * 0.06
                    for r in 0..<rows {
                        for c in 0..<cols {
                            ctx.fill(Path(roundedRect: CGRect(x: CGFloat(c) * cell + inset, y: CGFloat(r) * cell + inset, width: cell - inset * 2, height: cell - inset * 2),
                                          cornerRadius: cell * 0.2), with: .color(lab.surfaceAlt))
                        }
                    }
                }
                .frame(width: boardW, height: boardH)
                // Patches
                ForEach(game.level.clues.indices, id: \.self) { index in
                    PatchLayer(game: game, index: index, cell: cell, boardH: boardH)
                }
                // Drag preview
                if dragMoved, let start = dragStart, let current = dragCurrent {
                    DragPreview(game: game, rect: GridRect.spanning(start, current), cell: cell)
                }
                // Clue badges
                ForEach(Array(game.level.clues.enumerated()), id: \.offset) { index, clue in
                    let state: BadgeState = game.patches[index] == nil ? .Open : (game.isValid(index) ? .Satisfied : .Wrong)
                    ClueBadge(clue, state, cell, lab.patch(clue.k))
                        .frame(width: cell, height: cell)
                        .offset(x: cell * CGFloat(clue.c), y: cell * CGFloat(clue.r))
                }
            }
            .frame(width: boardW, height: boardH, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($touching) { _, t, _ in t = true }
                    .onChanged { v in changed(v, cell, rows, cols) }
                    .onEnded { v in ended(v, cell, rows, cols) }
            )
            .padding(pad)
            .background(
                LinearGradient(colors: [lab.surface.mix(.white, lab.isDark ? 0.07 : 0), lab.surface, lab.surface.mix(.black, lab.isDark ? 0.2 : 0.05)],
                               startPoint: .top, endPoint: .bottom)
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(lab.isDark ? 0.28 : 0.9), Color.black.opacity(0.12)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 2))
            .labShadow(Color.black.opacity(lab.isDark ? 0.25 : 0.08), 22, 10, corner)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(CGFloat(cols) / CGFloat(rows), contentMode: .fit)
        .onChange(of: touching) { _, down in
            // A cancelled touch never reaches `onEnded`: drop the half-drawn patch.
            if !down && dragStart != nil { dragStart = nil; dragCurrent = nil; dragMoved = false }
        }
        .onChange(of: game.placeCount) { _, count in
            if count == 0 { return }
            let area = game.lastPlaced.flatMap { game.patches[$0]?.area } ?? 1
            PuzzleSound.play(.Place(area), 0)
        }
    }

    private func cellAt(_ p: CGPoint, _ cell: CGFloat, _ rows: Int, _ cols: Int) -> Cell {
        Cell(Kt.toInt(Double(p.y / cell)).coerceIn(0, rows - 1), Kt.toInt(Double(p.x / cell)).coerceIn(0, cols - 1))
    }

    private func changed(_ v: DragGesture.Value, _ cell: CGFloat, _ rows: Int, _ cols: Int) {
        if dragStart == nil {
            let start = cellAt(v.startLocation, cell, rows, cols)
            dragStart = start
            dragCurrent = start
            dragMoved = false
        }
        let current = cellAt(v.location, cell, rows, cols)
        if current != dragCurrent {
            dragCurrent = current
            if dragMoved { Haptics.selection() }
        }
        if !dragMoved && hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y) > cell * 0.35 {
            dragMoved = true
            Haptics.selection()
        }
    }

    private func ended(_ v: DragGesture.Value, _ cell: CGFloat, _ rows: Int, _ cols: Int) {
        guard let start = dragStart else { return }
        let end = cellAt(v.location, cell, rows, cols)
        if dragMoved || start != end {
            game.place(GridRect.spanning(start, end))
        } else if game.tap(start) {
            PuzzleSound.play(.Remove)
            Haptics.impactLight()
        }
        dragStart = nil
        dragCurrent = nil
        dragMoved = false
    }
}

/// One clue's patch: springs between placements, fades and shrinks away when removed, pops in the
/// win wave and flashes when a hint reveals it.
private struct PatchLayer: View {
    let game: PatchesGame
    let index: Int
    let cell: CGFloat
    let boardH: CGFloat

    /// The last placed rect (kept after removal so the patch fades out where it was).
    @State private var shown: GridRect?
    @State private var visible = false
    @State private var win: CGFloat = 1
    @State private var glow: CGFloat = 0

    private static let move = labSpring(0.38, 0.72)

    var body: some View {
        let lab = Lab.colors
        let clue = game.level.clues[index]
        let s = shown ?? GridRect(clue.r, clue.c, 1, 1)
        PatchTile(x: CGFloat(s.col), y: CGFloat(s.row), w: CGFloat(s.width), h: CGFloat(s.height), glow: glow,
                  cell: cell, boardH: boardH, color: lab.patch(clue.k), valid: game.isValid(index), danger: lab.danger,
                  scale: (visible ? 1 : 0.7) * win, alpha: visible ? 1 : 0)
            .allowsHitTesting(false)
            .onChange(of: game.patches[index], initial: true) { old, rect in
                // The first call (on appear) shows a restored board as it is, like Compose's first frame.
                let initial = old == rect
                var still = Transaction()
                still.disablesAnimations = true
                if let rect {
                    if shown == nil {
                        withTransaction(still) { shown = rect } // first placement: no slide, just the pop-in
                    } else if rect != shown {
                        withAnimation(Self.move) { shown = rect }
                    }
                    if initial { withTransaction(still) { visible = true } } else { withAnimation(Self.move) { visible = true } }
                } else if !initial {
                    withAnimation(Self.move) { visible = false }
                }
            }
            // Win wave: each patch pops in turn, outward from the top-left corner.
            .task(id: game.isSolved) {
                guard game.isSolved, let sh = shown else { return }
                let center = Double(sh.row) + Double(sh.height) / 2 + Double(sh.col) + Double(sh.width) / 2
                do { try await Task.sleep(for: .milliseconds(Int(50 + center * 45))) } catch { return }
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.16)) { win = 1.1 }
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
                withAnimation(labSpring(0.4, 0.5)) { win = 1 }
            }
            // Hint glow on the revealed patch.
            .task(id: game.hintsUsed) {
                if game.hintsUsed == 0 || game.lastHintClue != index { return }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { glow = 0 }
                withAnimation(.linear(duration: 0.15)) { glow = 1 }
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                withAnimation(.linear(duration: 0.6)) { glow = 0 }
            }
    }
}

/// A patch tile at a (possibly animating) cell rect. Animatable, so the board-wide gradient and the
/// hint ring follow the spring frame by frame.
private struct PatchTile: View, Animatable {
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var glow: CGFloat
    let cell: CGFloat
    let boardH: CGFloat
    let color: Color
    let valid: Bool
    let danger: Color
    let scale: CGFloat
    let alpha: Double

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>, CGFloat> {
        get { AnimatablePair(AnimatablePair(AnimatablePair(x, y), AnimatablePair(w, h)), glow) }
        set {
            x = newValue.first.first.first
            y = newValue.first.first.second
            w = newValue.first.second.first
            h = newValue.first.second.second
            glow = newValue.second
        }
    }

    private static var margin: CGFloat { PatchTileMargin.value }

    var body: some View {
        let c = cell
        let inset = c * 0.06
        let m = Self.margin
        let left = x * c + inset
        let top = y * c + inset
        let width = max(0, w * c - inset * 2)
        let height = max(0, h * c - inset * 2)
        let radius = c * 0.22
        let gradient = color.softGradient(valid ? 1 : 0.55)
        let glow = glow
        let color = color
        let valid = valid
        let danger = danger
        let boardH = boardH
        Canvas { ctx, _ in
            let r = CGRect(x: m, y: m, width: width, height: height)
            // The Android brush spans the whole board: board top (y = 0) → board bottom.
            drawPatchTile(ctx, r, color, valid, radius, danger, glow, gradient: gradient,
                          from: m - top, to: m - top + boardH)
        }
        .frame(width: width + m * 2, height: height + m * 2)
        .scaleEffect(scale)
        .opacity(alpha)
        .offset(x: left - m, y: top - m)
    }
}

/// Room around a tile canvas for its shadow (3 sigma past the 4 pt drop) and the hint ring.
enum PatchTileMargin {
    static var value: CGFloat { (12.8 * shadowBlurScale * 3 + 4).rounded(.up) }
}

/// A placed patch: the clue colour's gradient, a white rim, a coloured shadow; dashed red when wrong.
/// The gradient runs from `from` to `to` (Compose brushes span the canvas, here the whole board).
@MainActor
func drawPatchTile(_ ctx: GraphicsContext, _ r: CGRect, _ color: Color, _ valid: Bool, _ radius: CGFloat, _ danger: Color, _ glow: CGFloat = 0,
                   gradient: Gradient? = nil, from: CGFloat? = nil, to: CGFloat? = nil) {
    ctx.shadowRoundRect(r, radius, color.copy(alpha: valid ? 0.45 : 0.15), 8 * 1.6, 4)
    let g = gradient ?? color.softGradient(valid ? 1 : 0.55)
    ctx.fill(Path(roundedRect: r, cornerRadius: radius),
             with: .linearGradient(g, startPoint: CGPoint(x: r.minX, y: from ?? r.minY), endPoint: CGPoint(x: r.minX, y: to ?? r.maxY)))
    let rim: CGFloat = 1.5
    ctx.stroke(Path(roundedRect: r.insetBy(dx: rim / 2, dy: rim / 2), cornerRadius: radius), with: .color(Color.white.opacity(0.4)), lineWidth: rim)
    if !valid {
        let w: CGFloat = 2.5
        ctx.stroke(Path(roundedRect: r.insetBy(dx: w / 2, dy: w / 2), cornerRadius: radius), with: .color(danger),
                   style: StrokeStyle(lineWidth: w, dash: [6, 4]))
    }
    if glow > 0 {
        let s = 1 + glow * 0.04
        let gr = CGRect(x: r.midX - r.width / 2 * s, y: r.midY - r.height / 2 * s, width: r.width * s, height: r.height * s)
        ctx.stroke(Path(roundedRect: gr, cornerRadius: radius), with: .color(Color.white.opacity(Double(min(glow, 1)))), lineWidth: 3)
    }
}

private struct DragPreview: View {
    let game: PatchesGame
    let rect: GridRect
    let cell: CGFloat

    var body: some View {
        let lab = Lab.colors
        let inside = game.cluesIn(rect)
        let clue = inside.count == 1 ? game.level.clues[inside[0]] : nil
        let color = clue.map { lab.patch($0.k) } ?? (inside.isEmpty ? lab.inkSecondary : lab.danger)
        let fits = clue?.accepts(rect) ?? false
        let inset = cell * 0.06
        let radius = cell * 0.22
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        ZStack(alignment: .top) {
            shape.fill(color.copy(alpha: 0.28))
            shape.inset(by: 1.25).stroke(color, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
            HStack(spacing: 4) {
                if fits { Icon(Icons.Rounded.Check, tint: .white, size: 11) }
                Text("\(rect.width)×\(rect.height) · \(rect.area)").font(rounded(12, .heavy)).foregroundStyle(Color.white).lineLimit(1)
                    .frame(height: 12 * 1.04 * 1.22)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(fits ? lab.ok : color))
            .clipShape(Capsule())
            .fixedSize()
            .offset(y: -26)
        }
        .frame(width: max(0, cell * CGFloat(rect.width) - inset * 2), height: max(0, cell * CGFloat(rect.height) - inset * 2))
        .offset(x: cell * CGFloat(rect.col) + inset, y: cell * CGFloat(rect.row) + inset)
        .allowsHitTesting(false)
    }
}

enum BadgeState { case Open, Satisfied, Wrong }

/// Horizontal shake for a wrong clue: three swings of 9 pt over one unit of `shakes`.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 9 * sin(shakes * .pi * 3 * 2), y: 0))
    }
}

/// The clue marker sitting on its cell.
struct ClueBadge: View {
    let clue: PatchesClue
    let state: BadgeState
    let cell: CGFloat
    let color: Color

    init(_ clue: PatchesClue, _ state: BadgeState, _ cell: CGFloat, _ color: Color) {
        self.clue = clue
        self.state = state
        self.cell = cell
        self.color = color
    }

    @State private var shakes: CGFloat = 0

    var body: some View {
        let lab = Lab.colors
        let size = cell * 0.66
        let state = state
        let color = color
        let textColor: Color = state == .Open ? .white : (state == .Wrong ? lab.danger : color)
        let pad = (4.8 * shadowBlurScale * 3 + 2).rounded(.up)
        ZStack {
            // Drawn with room around it so the soft shadow is never cut off.
            Canvas { ctx, s in
                let rect = CGRect(x: pad, y: pad, width: s.width - pad * 2, height: s.height - pad * 2)
                let r = min(rect.width, rect.height) / 2
                ctx.shadowRoundRect(rect, r, Color.black.opacity(state == .Open ? 0.18 : 0.1), 3 * 1.6, 2)
                let circle = Path(ellipseIn: rect)
                if state == .Open {
                    ctx.fill(circle, with: .linearGradient(color.softGradient(), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
                } else {
                    ctx.fill(circle, with: .color(.white))
                }
                if state == .Wrong {
                    ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1.25, dy: 1.25)), with: .color(lab.danger), lineWidth: 2.5)
                }
            }
            .frame(width: size + pad * 2, height: size + pad * 2)
            if let n = clue.n {
                Text("\(n)").font(rounded(size * 0.5 / 1.04, .heavy)).foregroundStyle(textColor).lineLimit(1)
                    .fixedSize()
            } else if let s = clue.s {
                ShapeGlyph(s, state == .Open ? .white : color)
                    .frame(width: size * 0.48, height: size * 0.48)
            }
            if let s = clue.s, clue.n != nil {
                let chip = size * 0.42
                ShapeGlyph(s, state == .Open ? color : .white)
                    .padding(3)
                    .frame(width: chip, height: chip)
                    .background(
                        Circle().fill(state == .Open
                                      ? AnyShapeStyle(Color.white)
                                      : AnyShapeStyle(LinearGradient(gradient: color.softGradient(), startPoint: .top, endPoint: .bottom)))
                    )
                    .clipShape(Circle())
                    .offset(x: size * 0.42, y: -size * 0.42)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(state == .Satisfied ? 0.88 : 1)
        .animation(labSpring(0.35, 0.55), value: state)
        .modifier(ShakeEffect(shakes: shakes))
        .onChange(of: state, initial: true) { _, s in
            if s == .Wrong {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { shakes = shakes.rounded(.down) }
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Icon for a clue's required shape.
struct ShapeGlyph: View {
    let shape: PatchShape
    let color: Color

    init(_ shape: PatchShape, _ color: Color) {
        self.shape = shape
        self.color = color
    }

    var body: some View {
        let shape = shape
        let color = color
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let s: CGSize
            switch shape {
            case .Square: s = CGSize(width: side * 0.78, height: side * 0.78)
            case .Wide: s = CGSize(width: side, height: side * 0.56)
            case .Tall: s = CGSize(width: side * 0.56, height: side)
            }
            ctx.fill(Path(roundedRect: CGRect(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2, width: s.width, height: s.height),
                          cornerRadius: side * 0.16), with: .color(color))
        }
    }
}

/// Board plus the shape legend, as shown inside the play shell.
struct PatchesPlayArea: View {
    let game: PatchesGame

    init(_ game: PatchesGame) { self.game = game }

    var body: some View {
        let lab = Lab.colors
        let shapes = Set(game.level.clues.compactMap { $0.s })
        VStack(spacing: 16) {
            PatchesBoard(game)
                .padding(.horizontal, 16)
                .layoutPriority(1)
            if !shapes.isEmpty {
                HStack(spacing: 14) {
                    ForEach([PatchShape.Square, .Wide, .Tall].filter { shapes.contains($0) }, id: \.self) { shape in
                        HStack(spacing: 5) {
                            ShapeGlyph(shape, lab.inkSecondary).frame(width: 13, height: 13)
                            Text(shape.title).font(rounded(12, .semibold)).foregroundStyle(lab.inkSecondary)
                        }
                    }
                    if game.level.clues.contains(where: { $0.n == nil }) {
                        Text("· any size").font(rounded(12, .semibold)).foregroundStyle(lab.inkSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(lab.surface.copy(alpha: 0.7)))
            } else {
                Text("Drag from a clue to draw a patch · tap to remove").font(rounded(12, .semibold)).foregroundStyle(lab.inkSecondary)
            }
        }
    }
}
