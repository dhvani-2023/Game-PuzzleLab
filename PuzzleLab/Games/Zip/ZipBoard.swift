import SwiftUI
import QuartzCore

enum ZipStyle {
    /// Oklab components of the three path stops (patch 0, 7, 6), per palette.
    private static let stopsDark = stops(DarkLab)
    private static let stopsLight = stops(LightLab)

    private static func stops(_ lab: LabPalette) -> [(Double, Double, Double, Double)] {
        colors(lab).map { c in
            let v = c.rgba
            let o = Oklab.from(v.r, v.g, v.b)
            return (o.0, o.1, o.2, v.a)
        }
    }

    static func colors(_ lab: LabPalette) -> [Color] { [lab.patch(0), lab.patch(7), lab.patch(6)] }

    /// Path colour for position `index` of a path that will cover `total` cells (perceptual blend),
    /// as sRGB components.
    static func rgba(_ lab: LabPalette, _ index: Int, _ total: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let s = lab.isDark ? stopsDark : stopsLight
        let t = total > 1 ? Float(index) / Float(total - 1) : 0
        let scaled = t * Float(s.count - 1)
        let i = min(Int(scaled), s.count - 2)
        let f = Double(scaled - Float(i))
        let a = s[i], b = s[i + 1]
        let rgb = Oklab.toSRGB(a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
        return (rgb.0, rgb.1, rgb.2, a.3 + (b.3 - a.3) * f)
    }

    static func color(_ lab: LabPalette, _ index: Int, _ total: Int) -> Color {
        let c = rgba(lab, index, total)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    /// `color(...).mix(Color.White, by)` (Oklab, like Compose `lerp`).
    static func brightened(_ lab: LabPalette, _ index: Int, _ total: Int, _ by: Double) -> Color {
        let c = rgba(lab, index, total)
        if by <= 0 { return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) }
        let t = min(by, 1)
        let o = Oklab.from(c.r, c.g, c.b)
        let w = Oklab.from(1, 1, 1)
        let rgb = Oklab.toSRGB(o.0 + (w.0 - o.0) * t, o.1 + (w.1 - o.1) * t, o.2 + (w.2 - o.2) * t)
        return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: c.a + (1 - c.a) * t)
    }
}

/// Animation curves of the board.
enum ZipMotion {
    /// A critically-damped settle 0 → 1 over about `ms`, the feel of SwiftUI's quick springs.
    static func settle(_ elapsedMs: Double, _ ms: Double) -> Double {
        if elapsedMs <= 0 { return 0 }
        let t = elapsedMs / ms * 6
        return min(max(1 - (1 + t) * exp(-t), 0), 1)
    }

    /// Overshooting spring 0 → 1 (scale pops).
    static func pop(_ elapsedMs: Double, _ response: Double, _ damping: Double) -> Double {
        if elapsedMs <= 0 { return 0 }
        let t = elapsedMs / 1000
        let w = 2 * Double.pi / response
        let zeta = damping
        let wd = w * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * w * t) * (cos(wd * t) + zeta * w / wd * sin(wd * t))
    }

    /// Milliseconds on the display clock.
    static func nowMs() -> Double { CACurrentMediaTime() * 1000 }
}

/// When each path cell appeared (ms), for the grow-in animations. A class so drawing never copies it.
final class ZipBornClock {
    var born: [Int: Double] = [:]
}

/// Interactive Zip board: drag from 1 to draw, drag back to undo part of the path.
struct ZipBoard: View {
    let game: ZipGame

    init(_ game: ZipGame) { self.game = game }

    @State private var clock = ZipBornClock()
    @State private var hintAt: Double = -1
    @State private var solvedAt: Double = -1
    @State private var lastSize = -1
    @State private var lastDots = -1
    @State private var stroking = false

    var body: some View {
        let lab = Lab.colors
        let level = game.level
        GeometryReader { geo in
            let pad: CGFloat = 8
            let cell = (min((geo.size.width - pad * 2) / CGFloat(level.cols), (geo.size.height - pad * 2) / CGFloat(level.rows))).rounded(.down)
            let corner = cell * 0.42
            let shape = RoundedRectangle(cornerRadius: corner, style: .circular)
            ZStack {
                TimelineView(.animation) { timeline in
                    let tick = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, _ in
                        _ = tick
                        ZipDraw.drawZip(&ctx, lab, level.rows, level.cols, level.dots, level.walls, game.path, cell,
                                        isSolved: game.isSolved, nextDot: game.nextDot, hintRange: game.hintRange,
                                        now: ZipMotion.nowMs(), born: clock.born, hintAt: hintAt, solvedAt: solvedAt)
                    }
                }
                .frame(width: cell * CGFloat(level.cols), height: cell * CGFloat(level.rows))
                .contentShape(Rectangle())
                .gesture(strokeGesture(cell))
                .padding(pad)
            }
            .frame(width: cell * CGFloat(level.cols) + pad * 2, height: cell * CGFloat(level.rows) + pad * 2)
            .background(
                LinearGradient(colors: [lab.surface.mix(.white, lab.isDark ? 0.07 : 0), lab.surface, lab.surface.mix(.black, lab.isDark ? 0.2 : 0.05)],
                               startPoint: .top, endPoint: .bottom)
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(lab.isDark ? 0.28 : 0.9), Color.black.opacity(0.12)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 2))
            .labShadow(Color.black.opacity(lab.isDark ? 0.25 : 0.08), 22, 10, corner)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(CGFloat(level.cols) / CGFloat(level.rows), contentMode: .fit)
        .onAppear { pathChanged() }
        .onChange(of: game.path) { pathChanged() }
        .onChange(of: game.hintsUsed) { _, n in if n > 0 { hintAt = ZipMotion.nowMs() } }
        .onChange(of: game.isSolved) { _, s in if s { solvedAt = ZipMotion.nowMs() } }
    }

    /// Kotlin `LaunchedEffect(game, game.path)`: grow-in clocks, the step tick and the dot chime.
    private func pathChanged() {
        let t = ZipMotion.nowMs()
        let path = game.path
        let first = lastSize < 0
        for cell in path where clock.born[cell] == nil { clock.born[cell] = first ? t - 10_000 : t }
        for key in Array(clock.born.keys) where game.pathIndex(key) == nil { clock.born[key] = nil }
        let size = path.count
        if !first && size > lastSize {
            PuzzleSound.play(.Step(size), 25)
            Haptics.selection()
        }
        lastSize = size
        let dots = game.visitedDots
        if !first && dots > lastDots && dots > 0 { PuzzleSound.play(.Dot(dots - 1), 0) }
        lastDots = dots
    }

    private func cellAt(_ p: CGPoint, _ cell: CGFloat, _ tolerance: CGFloat = 0) -> Int? {
        let level = game.level
        let x = p.x / cell
        let y = p.y / cell
        let col = Int(x.rounded(.down))
        let row = Int(y.rounded(.down))
        if row < 0 || row >= level.rows || col < 0 || col >= level.cols { return nil }
        if tolerance > 0 {
            let fx = x - CGFloat(col)
            let fy = y - CGFloat(row)
            if fx <= tolerance || fx >= 1 - tolerance || fy <= tolerance || fy >= 1 - tolerance { return nil }
        }
        return row * level.cols + col
    }

    private func strokeGesture(_ cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !stroking {
                    stroking = true
                    if let c = cellAt(value.startLocation, cell) { game.beginStroke(c) }
                    if value.location == value.startLocation { return }
                }
                if let c = cellAt(value.location, cell, 0.18) { game.drag(c) }
            }
            .onEnded { _ in
                stroking = false
                game.endStroke()
            }
    }
}

/// Draws a Zip board for a path. Used by the game and the demo artwork (Kotlin `DrawScope.drawZip`).
enum ZipDraw {
    static func drawZip(
        _ ctx: inout GraphicsContext,
        _ lab: LabPalette,
        _ rows: Int,
        _ cols: Int,
        _ dots: [Int],
        _ walls: [(first: Int, second: Int)],
        _ path: [Int],
        _ cell: CGFloat,
        isSolved: Bool = false,
        nextDot: Int? = nil,
        hintRange: ClosedRange<Int>? = nil,
        now: Double = 0,
        born: [Int: Double] = [:],
        hintAt: Double = -1,
        solvedAt: Double = -1,
        tile: Color? = nil,
        wallColor: Color? = nil
    ) {
        let total = rows * cols
        let thickness = cell * 0.38
        func center(_ i: Int) -> CGPoint { CGPoint(x: (CGFloat(i % cols) + 0.5) * cell, y: (CGFloat(i / cols) + 0.5) * cell) }
        var visited: [Int: Int] = [:]
        for (i, c) in path.enumerated() { visited[c] = i }
        func age(_ c: Int) -> Double { born[c].map { now - $0 } ?? 10_000 }
        let tileColor = tile ?? lab.surfaceAlt
        let wallFill = wallColor ?? lab.ink

        // Wells, tinted along the path.
        let inset = cell * 0.05
        for i in 0..<total {
            let r = CGRect(x: CGFloat(i % cols) * cell + inset, y: CGFloat(i / cols) * cell + inset, width: cell - inset * 2, height: cell - inset * 2)
            let well = Path(roundedRect: r, cornerRadius: cell * 0.2, style: .circular)
            ctx.fill(well, with: .color(tileColor))
            if let order = visited[i] { ctx.fill(well, with: .color(ZipStyle.color(lab, order, total).opacity(0.22))) }
        }

        // Segments grow out of the previous cell's centre.
        let hintElapsed = hintAt >= 0 ? now - hintAt : -1
        let winElapsed = solvedAt >= 0 ? now - solvedAt : -1
        if path.count > 1 {
            for index in 1..<path.count {
                let a = center(path[index - 1])
                var b = center(path[index])
                let g = CGFloat(ZipMotion.settle(age(path[index]), 260))
                b = CGPoint(x: a.x + (b.x - a.x) * g, y: a.y + (b.y - a.y) * g)
                var w = thickness
                var bright = 0.0
                if winElapsed >= 0 {
                    let local = winElapsed - Double(50 + index * 18)
                    if local > 0 {
                        let up = local < 140 ? local / 140 : 1
                        let p = ZipMotion.pop(local - 140, 0.35, 0.5)
                        let s = local < 140 ? 1 + 0.22 * up : 1.22 - 0.22 * p
                        w *= CGFloat(s)
                        bright = (s - 1) * 2.5
                    }
                }
                let start = ZipStyle.brightened(lab, index - 1, total, bright)
                let end = ZipStyle.brightened(lab, index, total, bright)
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)
                let to = b == a ? CGPoint(x: a.x + 0.1, y: a.y + 0.1) : b
                ctx.stroke(line, with: .linearGradient(Gradient(colors: [start, end]), startPoint: a, endPoint: to),
                           style: StrokeStyle(lineWidth: w, lineCap: .round))
                if let hintRange, hintRange.contains(index), hintElapsed >= 0 {
                    let local = hintElapsed - Double(index - hintRange.lowerBound) * 40
                    let alpha: Double
                    if local < 0 { alpha = 0 } else if local < 150 { alpha = local / 150 * 0.75 } else if local < 650 { alpha = 0.75 * (1 - (local - 150) / 500) } else { alpha = 0 }
                    if alpha > 0 { ctx.stroke(line, with: .color(Color.white.opacity(alpha)), style: StrokeStyle(lineWidth: w, lineCap: .round)) }
                }
            }
        }
        // Round caps hide the seams where segments meet.
        for (index, c) in path.enumerated() {
            let s = 0.2 + 0.8 * CGFloat(ZipMotion.settle(age(c), 200))
            let r = thickness / 2 * s
            let p = center(c)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(ZipStyle.color(lab, index, total)))
        }
        // Breathing glow at the head.
        if let last = path.last, !isSolved {
            let head = center(last)
            let breath = 0.875 + 0.125 * CGFloat(sin(now / 800 * Double.pi))
            let r = thickness * 0.95 * breath
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                     with: .color(ZipStyle.color(lab, path.count - 1, total).opacity(0.35)))
        }
        // Walls.
        for wall in walls {
            let a = min(wall.first, wall.second)
            let b = max(wall.first, wall.second)
            let horizontalNeighbours = b - a == 1
            let length = cell * 0.92
            let weight = max(4, cell * 0.11)
            let x = horizontalNeighbours ? CGFloat(b % cols) * cell - weight / 2 : CGFloat(a % cols) * cell + (cell - length) / 2
            let y = horizontalNeighbours ? CGFloat(a / cols) * cell + (cell - length) / 2 : CGFloat(b / cols) * cell - weight / 2
            let r = CGRect(x: x, y: y, width: horizontalNeighbours ? weight : length, height: horizontalNeighbours ? length : weight)
            ctx.shadowRoundRect(r, weight / 2, Color.black.opacity(0.18), 4, 1)
            ctx.fill(Path(roundedRect: r, cornerRadius: weight / 2, style: .circular), with: .color(wallFill))
        }
        // Numbered dots.
        let size = cell * 0.62
        let font = Nunito.font(size * 0.48, FontWeight.ExtraBold)
        for (rank, c) in dots.enumerated() {
            let order = visited[c]
            let p = center(c)
            let scale = order != nil ? 1 + 0.08 * CGFloat(ZipMotion.pop(age(c), 0.3, 0.45)) : 1
            if rank == nextDot && !isSolved {
                let ph = CGFloat(now.truncatingRemainder(dividingBy: 1200) / 1200)
                let rr = size / 2 * (1 + 0.6 * ph)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                           with: .color(lab.ink.opacity(Double(0.5 * (1 - ph)))), lineWidth: 2)
            }
            var dc = ctx
            dc.translateBy(x: p.x, y: p.y)
            dc.scaleBy(x: scale, y: scale)
            let box = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            dc.shadowRoundRect(box, size / 2, Color.black.opacity(0.22), 6, 2)
            dc.fill(Path(ellipseIn: box), with: .color(lab.ink))
            if let order {
                let ring = max(2.5, size * 0.1)
                let rr = size / 2 - ring / 2
                dc.stroke(Path(ellipseIn: CGRect(x: -rr, y: -rr, width: rr * 2, height: rr * 2)), with: .color(ZipStyle.color(lab, order, total)), lineWidth: ring)
            }
            dc.draw(Text("\(rank + 1)").font(font).foregroundColor(lab.surface), at: .zero, anchor: .center)
        }
    }
}
