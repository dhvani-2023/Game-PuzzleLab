import SwiftUI
import CoreText
import GameKit

/// Screen positions the "+1" flights travel between (play-screen coordinates).
private final class Spots {
    var board = CGPoint.zero
    var you = CGPoint.zero
    var rival = CGPoint.zero
}

private let boxPlaySpace = "boxBattlePlay"
/// Compose `fadeIn()` / `fadeOut()` / `scaleIn()` default: a critically damped spring, StiffnessMediumLow.
private let boxFade = Animation.compose(dampingRatio: 1, stiffness: 400)

private struct SessionKey: Equatable {
    let session: ObjectIdentifier
    let a: Int
    let b: Int
}

struct BoxBattlePlay: View {
    let startLevel: Int

    init(_ startLevel: Int) {
        self.startLevel = startLevel
        let pack = BoxBattleModule.shared.pack
        let id = pack.level(startLevel) == nil ? 1 : startLevel
        _levelID = State(initialValue: id)
        _session = State(initialValue: BoxBattleSession(pack.level(id)!))
        _fx = State(initialValue: BoxFx(Lab.reduceMotion))
    }

    @Environment(AppState.self) private var app
    @State private var levelID: Int
    @State private var session: BoxBattleSession
    @State private var fx: BoxFx
    @State private var clock = FxClock()
    @State private var spots = Spots()
    @State private var showWin = false
    @State private var showLoss = false
    @State private var showHowTo = false
    @State private var isNewBest = false
    @State private var shownYou = 0
    @State private var shownRival = 0
    @State private var botSteps = 0

    private var module: BoxBattleModule { BoxBattleModule.shared }

    private func reload() {
        withAnimation(boxFade) { showWin = false; showLoss = false }
        session = BoxBattleSession(module.pack.level(levelID)!)
        fx = BoxFx(Lab.reduceMotion)
        clock.fx = fx
        shownYou = 0
        shownRival = 0
    }

    private func openLevels() { app.router.backToLevels(module.info.id) }

    private func captureFeedback(_ n: Int, mine: Bool) {
        if n <= 0 { return }
        PuzzleSound.play(.Star)
        if mine { Haptics.impactMedium() } else { Haptics.impactLight() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            PuzzleSound.play(.Clear)
        }
    }

    private func playerEdge(_ e: BoxEdge, _ viaTap: Bool) {
        guard let claimed = session.playerDraw(e) else {
            fx.cancelDrag(clock.now)
            clock.wake()
            return
        }
        fx.commit(e, clock.now, grow: viaTap ? 0.12 : 0)
        PuzzleSound.play(.Place(3))
        Haptics.impactLight()
        for b in claimed { fx.capture(b.r, b.c, .You, clock.now) }
        clock.wake()
        captureFeedback(claimed.count, mine: true)
    }

    var body: some View {
        let info = module.info
        let reduce = Lab.reduceMotion
        let sid = ObjectIdentifier(session)
        ZStack {
            LabBackground()

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    GameBackButton { app.router.pop() }
                    Spacer(minLength: 0)
                    LevelTag(level: levelID)
                    Spacer(minLength: 0)
                    GameIconButton(Icons.Rounded.Replay, colors: GameColors.slate()) { UISound.whoosh(); reload() }
                }
                Spacer().frame(height: 14)
                HStack(spacing: 10) {
                    ScorePill(score: shownYou, colors: BoxArt.key(.You))
                        .onGeometryChange(for: CGPoint.self) { p in
                            let f = p.frame(in: .named(boxPlaySpace))
                            return CGPoint(x: f.midX, y: f.midY)
                        } action: { spots.you = $0 }
                    TurnPill(turn: session.turn, phase: session.phase)
                    ScorePill(score: shownRival, colors: BoxArt.key(.Rival))
                        .onGeometryChange(for: CGPoint.self) { p in
                            let f = p.frame(in: .named(boxPlaySpace))
                            return CGPoint(x: f.midX, y: f.midY)
                        } action: { spots.rival = $0 }
                }
                .frame(maxWidth: .infinity)
                BoxBoard(session: session, fx: fx, clock: clock, spots: spots, onEdge: playerEdge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer().frame(height: 10)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            FlyingPoints(clock: clock, fx: fx, spots: spots)

            if showLoss {
                LossCard(session: session, onRetry: { UISound.whoosh(); reload() }, onLevels: openLevels)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9)), removal: .opacity))
                    .zIndex(1)
            }

            if showWin {
                LevelCompleteView(
                    module: module,
                    levelID: levelID,
                    time: session.elapsedSeconds,
                    bestTime: app.store.progress(info.id).record(levelID)?.bestTime,
                    isNewBest: isNewBest,
                    stars: session.stars,
                    hintsUsed: 3 - session.stars,
                    isLastLevel: levelID >= module.pack.count,
                    onNext: {
                        if module.pack.level(levelID + 1) == nil { openLevels() } else { levelID += 1; reload() }
                    },
                    onReplay: { reload() },
                    onLevels: openLevels,
                    extraStat: ExtraStat("Coins", "+\(session.coinsEarned)", Icons.Rounded.MonetizationOn),
                    subtitle: "You \(session.scoreYou) · Rival \(session.scoreRival)"
                )
                .transition(.opacity)
                .zIndex(2)
            }
            if showHowTo {
                HowToPlaySheet(module) { showHowTo = false }
                    .zIndex(3)
            }
        }
        .coordinateSpace(name: boxPlaySpace)
        .onAppear {
            clock.fx = fx
            clock.wake()
        }
        .onDisappear { clock.stop() }
        .task {
            app.store.markPlayed(info.id)
            let key = "howToPlay.\(info.id).seen"
            if !Prefs.bool(key) {
                Prefs.putBool(key, true)
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                showHowTo = true
            }
        }
        // The Rival's turn: think, draw the line with its pencil, then commit it.
        .task(id: SessionKey(session: sid, a: session.turn == .You ? 0 : 1, b: session.revision)) {
            let s = session
            let fx = fx
            guard s.botThinking else { return }
            let wait = s.lastClaimed > 0 ? Int(BoxFx.CAPTURE_SECONDS * 1000) : 520
            do { try await Task.sleep(for: .milliseconds(wait)) } catch { return }
            guard let e = s.chooseBotEdge() else { return }
            fx.startPencil(e, clock.now)
            clock.wake()
            do { try await Task.sleep(for: .milliseconds(Int(fx.pencilSeconds * 1000))) } catch { return }
            let claimed = s.commitBot(e)
            fx.commit(e, clock.now)
            PuzzleSound.play(.Step(botSteps))
            botSteps += 1
            Haptics.selection()
            for b in claimed { fx.capture(b.r, b.c, .Rival, clock.now) }
            clock.wake()
            captureFeedback(claimed.count, mine: false)
        }
        // Scores tick up as each "+1" lands in its pill.
        .task(id: SessionKey(session: sid, a: session.scoreYou, b: 0)) {
            let s = session
            if s.scoreYou != shownYou {
                do { try await Task.sleep(for: .milliseconds(reduce ? 20 : Int(BoxFx.FLY_FOR * 1000))) } catch { return }
                shownYou = s.scoreYou
                PuzzleSound.play(.Dot(shownYou % 10))
            }
        }
        .task(id: SessionKey(session: sid, a: session.scoreRival, b: 1)) {
            let s = session
            if s.scoreRival != shownRival {
                do { try await Task.sleep(for: .milliseconds(reduce ? 20 : Int(BoxFx.FLY_FOR * 1000))) } catch { return }
                shownRival = s.scoreRival
            }
        }
        .task(id: SessionKey(session: sid, a: session.phase == .Won ? 1 : (session.phase == .Lost ? 2 : 0), b: 0)) {
            let s = session
            switch s.phase {
            case .Won:
                isNewBest = app.store.recordSolve(info.id, levelID, s.elapsedSeconds, 3 - s.stars, s.stars)
                do { try await Task.sleep(for: .milliseconds(reduce ? 300 : 1350)) } catch { return }
                Haptics.success()
                PuzzleSound.play(.Win)
                withAnimation(boxFade) { showWin = true }
            case .Lost:
                do { try await Task.sleep(for: .milliseconds(reduce ? 300 : 1350)) } catch { return }
                Haptics.warning()
                PuzzleSound.play(.Error)
                withAnimation(boxFade) { showLoss = true }
            case .Playing:
                break
            }
        }
    }
}

// MARK: - Board

/// Per-touch bookkeeping (a reference, so finger moves never re-render the screen).
private final class BoardTouch {
    var active = false
    var down = CGPoint.zero
    var last = CGPoint.zero
    var start = -1
    var dragging = false
    var moved: CGFloat = 0
    var geom: BoardGeom?
}

/// The square board: the settled layer, the live layer on top, and the drag / tap input.
private struct BoxBoard: View {
    let session: BoxBattleSession
    let fx: BoxFx
    let clock: FxClock
    let spots: Spots
    let onEdge: (BoxEdge, Bool) -> Void

    @State private var touch = BoardTouch()
    /// True while a finger is down; resets by itself if the system cancels the touch.
    @GestureState private var touching = false

    var body: some View {
        GeometryReader { geo in
            let side = max(1, min(geo.size.width, geo.size.height, 480))
            Color.clear
                .frame(width: side, height: side)
                .overlay {
                    BoxStaticLayer(key: clock.staticKey, fx: fx, model: session.model, side: side).equatable()
                }
                .overlay {
                    BoxDynamicLayer(clock: clock, fx: fx, model: session.model, side: side)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .updating($touching) { _, t, _ in t = true }
                        .onChanged { v in changed(v, side) }
                        .onEnded { v in ended(v, side) }
                )
                .onGeometryChange(for: CGPoint.self) { p in p.frame(in: .named(boxPlaySpace)).origin } action: { spots.board = $0 }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onChange(of: touching) { _, down in
            // A cancelled touch never reaches `onEnded`: let the line snap back.
            if !down && touch.active {
                touch.active = false
                if touch.dragging {
                    fx.cancelDrag(clock.now)
                    clock.wake()
                }
            }
        }
    }

    /// Press a dot and drag toward a neighbour: the line follows, snaps on, and commits on release.
    private func changed(_ v: DragGesture.Value, _ side: CGFloat) {
        let model = session.model
        if !touch.active {
            touch.active = true
            touch.down = v.startLocation
            touch.last = v.startLocation
            touch.moved = 0
            let g = BoardGeom.of(side, side, model.rows, model.cols)
            touch.geom = g
            touch.start = nearestDot(g, v.startLocation, g.cell * 0.46)
            touch.dragging = touch.start >= 0 && session.canPlayerMove
            if touch.dragging {
                fx.beginDrag(touch.start, clock.now)
                clock.wake()
                Haptics.selection()
            }
        }
        move(v.location)
    }

    private func move(_ p: CGPoint) {
        guard let g = touch.geom, p != touch.last else { return }
        touch.last = p
        touch.moved = max(touch.moved, hypot(p.x - touch.down.x, p.y - touch.down.y))
        if touch.dragging {
            let (head, hover) = dragTarget(g, session.model, touch.start, p)
            if fx.updateDrag(head, hover, clock.now) {
                Haptics.selection()
                UISound.tap()
            }
        }
    }

    private func ended(_ v: DragGesture.Value, _ side: CGFloat) {
        defer { touch.active = false }
        guard touch.active, let g = touch.geom else { return }
        move(v.location)
        if touch.dragging && fx.hoverDot >= 0 {
            onEdge(edgeBetween(g, touch.start, fx.hoverDot), false)
        } else if touch.dragging {
            fx.cancelDrag(clock.now)
            clock.wake()
        } else if touch.moved < g.cell * 0.3 && session.canPlayerMove {
            if let e = edgeNearPoint(g, session.model, touch.down) { onEdge(e, true) }
        }
    }
}

/// Board card, settled lines and finished scribbles. Redraws only when `key` changes.
private struct BoxStaticLayer: View, Equatable {
    let key: Int
    let fx: BoxFx
    let model: BoxModel
    let side: CGFloat
    private let ids: [ObjectIdentifier]

    init(key: Int, fx: BoxFx, model: BoxModel, side: CGFloat) {
        self.key = key
        self.fx = fx
        self.model = model
        self.side = side
        ids = [ObjectIdentifier(fx), ObjectIdentifier(model)]
    }

    nonisolated static func == (a: BoxStaticLayer, b: BoxStaticLayer) -> Bool {
        a.key == b.key && a.ids == b.ids && a.side == b.side
    }

    var body: some View {
        let margin = (side * 0.08).rounded(.up)
        let key = key
        let side = side
        let fx = fx
        let model = model
        Canvas { ctx, _ in
            _ = key
            var c = ctx
            c.translateBy(x: margin, y: margin)
            fx.drawStatic(c, CGSize(width: side, height: side), model)
        }
        .frame(width: side + margin * 2, height: side + margin * 2)
        .allowsHitTesting(false)
    }
}

/// Everything that moves: springing lines, the pencil, the drag line, glow traces, dots and pencils.
private struct BoxDynamicLayer: View {
    let clock: FxClock
    let fx: BoxFx
    let model: BoxModel
    let side: CGFloat

    var body: some View {
        let tick = clock.frame
        let now = clock.now
        let margin = (side * 0.2).rounded(.up)
        let side = side
        let fx = fx
        let model = model
        Canvas { ctx, _ in
            _ = tick
            var c = ctx
            c.translateBy(x: margin, y: margin)
            fx.drawDynamic(c, CGSize(width: side, height: side), model, now)
        }
        .frame(width: side + margin * 2, height: side + margin * 2)
        .allowsHitTesting(false)
    }
}

private func nearestDot(_ g: BoardGeom, _ p: CGPoint, _ radius: CGFloat) -> Int {
    let c = Kt.roundToInt(Double((p.x - g.origin.x) / g.cell)).coerceIn(0, g.cols)
    let r = Kt.roundToInt(Double((p.y - g.origin.y) / g.cell)).coerceIn(0, g.rows)
    let d = g.dot(r, c)
    return hypot(p.x - d.x, p.y - d.y) <= radius ? g.index(r, c) : -1
}

/// Where the live line's head goes for a finger at `p`, and the dot it has snapped to (or -1).
private func dragTarget(_ g: BoardGeom, _ model: BoxModel, _ start: Int, _ p: CGPoint) -> (CGPoint, Int) {
    let r = start / (g.cols + 1)
    let c = start % (g.cols + 1)
    let o = g.dot(r, c)
    let vx = p.x - o.x
    let vy = p.y - o.y
    let horizontal = abs(vx) >= abs(vy)
    let comp = horizontal ? vx : vy
    let dir: CGFloat = comp >= 0 ? 1 : -1
    let step = comp >= 0 ? 1 : -1
    let nr = horizontal ? r : r + step
    let nc = horizontal ? c + step : c
    if !(0...g.rows).contains(nr) || !(0...g.cols).contains(nc) { return (o, -1) }
    let free = !model.isDrawn(edgeBetween(g, start, g.index(nr, nc)))
    if free && abs(comp) > g.cell * 0.58 { return (g.dot(nr, nc), g.index(nr, nc)) }
    let len = min(abs(comp), g.cell * (free ? 1 : 0.6)) * dir
    return (horizontal ? CGPoint(x: o.x + len, y: o.y) : CGPoint(x: o.x, y: o.y + len), -1)
}

private func edgeBetween(_ g: BoardGeom, _ a: Int, _ b: Int) -> BoxEdge {
    let r0 = a / (g.cols + 1), c0 = a % (g.cols + 1)
    let r1 = b / (g.cols + 1), c1 = b % (g.cols + 1)
    return r0 == r1 ? BoxEdge(true, r0, min(c0, c1)) : BoxEdge(false, min(r0, r1), c0)
}

/// Tap fallback: the nearest free line to a tap between dots.
private func edgeNearPoint(_ g: BoardGeom, _ model: BoxModel, _ p: CGPoint) -> BoxEdge? {
    var best: BoxEdge?
    var bestD = g.cell * 0.4
    for r in 0...g.rows {
        for c in 0..<g.cols {
            let e = BoxEdge(true, r, c)
            if model.isDrawn(e) { continue }
            let d = hypot(p.x - (g.dot(r, c).x + g.cell / 2), p.y - g.dot(r, c).y)
            if d < bestD { bestD = d; best = e }
        }
    }
    for r in 0..<g.rows {
        for c in 0...g.cols {
            let e = BoxEdge(false, r, c)
            if model.isDrawn(e) { continue }
            let d = hypot(p.x - g.dot(r, c).x, p.y - (g.dot(r, c).y + g.cell / 2))
            if d < bestD { bestD = d; best = e }
        }
    }
    return best
}

// MARK: - "+1" flights

/// The "+1" in Nunito Black 34, as one outline path centred on the origin (built once).
private enum PlusOne {
    static let path: Path = {
        let font = Nunito.uiFont(34, .black) as CTFont
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "+1", attributes: [.font: font]))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let baseline = (ascent - descent) / 2
        let out = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = attrs[kCTFontAttributeName as String].map { $0 as! CTFont } ?? font
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for i in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                let t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[i].x - width / 2, ty: baseline)
                out.addPath(glyph, transform: t)
            }
        }
        return Path(out)
    }()
}

/// "+1"s popping out of captured boxes and flying into the scorer's pill.
private struct FlyingPoints: View {
    let clock: FxClock
    let fx: BoxFx
    let spots: Spots

    private static let ink = hex(0x1A1B22)
    // Android strokes the text 9 px and 4 px wide on a 2 px-per-dp phone.
    private static let outer = StrokeStyle(lineWidth: 4.5, lineJoin: .round)
    private static let inner = StrokeStyle(lineWidth: 2, lineJoin: .round)

    var body: some View {
        let tick = clock.frame
        let now = clock.now
        let fx = fx
        let spots = spots
        Canvas { ctx, _ in
            _ = tick
            if fx.flyers.isEmpty { return }
            let glyph = PlusOne.path
            fx.flyerFrames(now, spots.board, spots.you, spots.rival) { pos, s, owner in
                if s <= 0.01 { return }
                var c = ctx
                c.translateBy(x: pos.x, y: pos.y)
                c.scaleBy(x: s, y: s)
                c.stroke(glyph, with: .color(Self.ink), style: Self.outer)
                c.stroke(glyph, with: .color(.white), style: Self.inner)
                c.fill(glyph, with: .color(BoxArt.line(owner)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - HUD

/// The dark "LV n" tag.
private struct LevelTag: View {
    let level: Int

    var body: some View {
        GameKey(colors: [hex(0x4A4D5A), hex(0x2A2C35)], corner: 14, depth: 4, onClick: nil) {
            HStack(alignment: .bottom, spacing: 0) {
                Text("LV").font(gameTextStyle(15)).foregroundStyle(hex(0xD3D5DE))
                Spacer().frame(width: 5)
                Text("\(level)").font(gameTextStyle(21)).foregroundStyle(Color.white)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
    }
}

/// A chunky 3D score pill that bumps each time its score goes up.
private struct ScorePill: View {
    let score: Int
    let colors: [Color]
    @State private var bumps = 0

    var body: some View {
        GameKey(colors: colors, corner: 17, depth: 5, fill: true, onClick: nil) {
            Text("\(score)").font(gameTextStyle(28)).foregroundStyle(Color.white)
        }
        .frame(width: 66, height: 60)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: bumps) { content, s in
            content.scaleEffect(s)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(CGFloat(1.3))
                SpringKeyframe(CGFloat(1), duration: 1, spring: Spring(response: 0.36, dampingRatio: 0.4))
            }
        }
        .onChange(of: score) { _, new in if new > 0 { bumps += 1 } }
    }
}

/// The white "YOUR / TURN" pill, cross-fading to the Rival's turn.
private struct TurnPill: View {
    let turn: Player
    let phase: BoxBattleSession.Phase

    var body: some View {
        let state = phase != .Playing ? 2 : (turn == .You ? 0 : 1)
        GameKey(colors: GameColors.white, corner: 17, depth: 5, fill: true, onClick: nil) {
            ZStack {
                TurnLabel(state: state)
                    .id(state)
                    .transition(.opacity)
            }
            .animation(tween(300), value: state)
        }
        .frame(width: 136, height: 60)
    }
}

private struct TurnLabel: View {
    let state: Int

    var body: some View {
        let top: String
        let color: Color
        switch state {
        case 0: top = "YOUR"; color = BoxArt.you
        case 1: top = "RIVAL'S"; color = BoxArt.rival
        default: top = "BOARD"; color = hex(0x6B6F86)
        }
        return VStack(spacing: 0) {
            // Compose line boxes are 1.22 × the font size; keep the two lines that tall.
            Text(top).font(gameTextStyle(22, shadowColor: .clear)).foregroundStyle(color)
                .frame(height: 22 * 1.04 * 1.22)
            Text(state == 2 ? "FULL" : "TURN").font(rounded(13, .black, tracking: 1)).foregroundStyle(hex(0xA3A7B8))
                .frame(height: 13 * 1.04 * 1.22)
        }
    }
}

private struct LossCard: View {
    let session: BoxBattleSession
    let onRetry: () -> Void
    let onLevels: () -> Void

    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 14) {
            Text(session.scoreYou == session.scoreRival ? "It's a draw" : "Rival wins").font(LabText.title).foregroundStyle(lab.ink)
            Text("You \(session.scoreYou) · Rival \(session.scoreRival)").font(LabText.body).foregroundStyle(lab.ink2)
            Text("Own more boxes than your rival to clear the level.").font(LabText.caption).foregroundStyle(lab.ink2)
                .fixedSize(horizontal: false, vertical: true)
            GameButton("Try again", fill: true, colors: BoxArt.key(.You), onClick: onRetry)
            GameButton("Level map", fill: true, colors: GameColors.slate(), onClick: onLevels)
        }
        .padding(26)
        .frame(maxWidth: 360)
        .gamePopup(32, BoxArt.key(.Rival))
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
