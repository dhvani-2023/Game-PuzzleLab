import SwiftUI
import GameKit

/// Kotlin `"%,d".format(n)` (English grouping), without a formatter per call (the score counts up every frame).
func tileGrouped(_ n: Int) -> String {
    let digits = String(abs(n))
    var out = ""
    out.reserveCapacity(digits.count + digits.count / 3 + 1)
    for (i, ch) in digits.enumerated() {
        if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return n < 0 ? "-" + out : out
}

func goalText(_ goal: TileGoal, _ total: Int) -> String {
    switch goal.kind {
    case .Collect: return "Collect \(total) \(total == 1 ? (goal.gem ?? .Star).title : (goal.gem ?? .Star).plural)"
    case .Score: return "Score \(tileGrouped(total)) points"
    case .Clear: return "Clear all \(total) starting blocks"
    }
}

private struct GoalIcon: View {
    let goal: TileGoal
    let size: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        let lab = Lab.colors
        let px = max(1, Int((size * scale).rounded()))
        switch goal.kind {
        case .Collect:
            TileArt.gem(goal.gem ?? .Star, px).image(scale: scale).resizable().frame(width: size, height: size)
        case .Clear:
            TileArt.block(5, px).image(scale: scale).resizable().frame(width: size, height: size)
        case .Score:
            Icon(Icons.Rounded.Star, tint: lab.sun, size: size - 6)
                .frame(width: size, height: size)
                .background(Circle().fill(lab.sun.copy(alpha: 0.25)))
        }
    }
}

/** The Tile Burst screen: the board scene, the HUD and every card (intro, revive, loss, score, win). */
struct TileBurstPlay: View {
    let startLevel: Int
    let startMode: TileBurstSession.Mode

    @State private var levelID: Int
    @State private var session: TileBurstSession
    @State private var showPause = false
    @State private var confirmQuit = false
    @State private var showHowTo = false
    @State private var showWin = false
    @State private var isNewBest = false
    @Environment(\.scenePhase) private var scenePhase

    init(_ startLevel: Int, _ startMode: TileBurstSession.Mode) {
        self.startLevel = startLevel
        self.startMode = startMode
        let pack = TileBurstModule.pack
        let id = pack.level(startLevel) == nil ? 1 : startLevel
        _levelID = State(initialValue: id)
        _session = State(initialValue: TileBurstSession(startMode, pack.level(id), Lab.reduceMotion))
    }

    private var app: AppState { LocalApp.current }
    private var info: GameInfo { TileBurstModule.info }

    private func reload(_ mode: TileBurstSession.Mode, _ start: Bool) {
        showWin = false
        let fresh = TileBurstSession(mode, TileBurstModule.pack.level(levelID), Lab.reduceMotion)
        session = fresh
        if start {
            TileSound.play(.Deal)
            fresh.start()
        }
    }

    private func openLevels() { app.router.backToLevels(info.id) }

    private struct PhaseKey: Equatable {
        let session: ObjectIdentifier
        let phase: TileBurstSession.Phase
    }

    var body: some View {
        let s = session
        let ready = s.phase == .Ready
        ZStack {
            TileSceneView(session: s)

            // HUD
            VStack(spacing: 8) {
                TopBar(session: s, levelID: levelID, dim: ready ? 0.3 : 1, onBack: {
                    if s.phase == .Ready { app.router.pop() } else { s.pause(); showPause = true }
                })
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .animation(tween(300), value: ready)

            if ready {
                IntroCard(session: s, level: TileBurstModule.pack.level(levelID), onMode: { mode in
                    if mode != s.mode { reload(mode, false) }
                }, onStart: {
                    TileSound.play(.Deal)
                    Haptics.cta()
                    s.start()
                }, onHowTo: { showHowTo = true })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.92)).animation(.spring(response: 0.45, dampingFraction: 1)),
                                        removal: AnyTransition.opacity.combined(with: .scale(scale: 0.92)).animation(tween(200))))
            }
            if s.phase == .NoSpace { ReviveCard(session: s) }
            if s.phase == .Over {
                if s.mode == .Adventure {
                    LossCard(session: s, onRetry: { reload(s.mode, true) }, onLevels: openLevels)
                } else {
                    ScoreCard(session: s, onAgain: { reload(s.mode, true) }, onModes: { reload(s.mode, false) })
                }
            }
            if showWin, let level = s.level {
                LevelCompleteView(
                    module: TileBurstModule.shared,
                    levelID: level.id,
                    time: s.elapsedSeconds,
                    bestTime: app.store.progress(info.id).record(level.id)?.bestTime,
                    isNewBest: isNewBest,
                    stars: s.stars,
                    hintsUsed: 3 - s.stars,
                    isLastLevel: level.id >= TileBurstModule.pack.count,
                    onNext: {
                        if TileBurstModule.pack.level(levelID + 1) == nil { openLevels() } else { levelID += 1; reload(.Adventure, false) }
                    },
                    onReplay: { reload(s.mode, true) },
                    onLevels: openLevels,
                    extraStat: ExtraStat("Coins", "+\(s.coinsEarned)", Icons.Rounded.MonetizationOn)
                )
                .transition(.asymmetric(insertion: AnyTransition.opacity.animation(tween(300)), removal: AnyTransition.opacity.animation(tween(200))))
            }
            if showPause {
                PauseSheet(
                    confirmQuit: confirmQuit,
                    onResume: { showPause = false; s.resume() },
                    onRestart: { showPause = false; reload(s.mode, true) },
                    onQuit: { confirmQuit = true },
                    onKeep: { confirmQuit = false },
                    onLeave: { showPause = false; app.router.pop() }
                )
            }
            if showHowTo { HowToPlaySheet(TileBurstModule.shared) { showHowTo = false } }
        }
        .task {
            app.store.markPlayed(info.id)
            let key = "howToPlay.\(info.id).seen"
            if !Prefs.bool(key) {
                Prefs.putBool(key, true)
                try? await Task.sleep(nanoseconds: 500_000_000)
                showHowTo = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { s.pause() } else if !showPause { s.resume() }
        }
        .task(id: PhaseKey(session: ObjectIdentifier(s), phase: s.phase)) {
            switch s.phase {
            case .Won:
                guard let level = s.level else { return }
                isNewBest = app.store.recordSolve(info.id, level.id, s.elapsedSeconds, 3 - s.stars, s.stars)
                Haptics.success()
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                withAnimation(tween(300)) { showWin = true }
            case .Over:
                if s.isNewBest { TileSound.play(.NewBest); Haptics.success() }
            default:
                break
            }
        }
        // Haptics for the run.
        .onChange(of: s.pickTick) { _, v in if v > 0 { Haptics.selection() } }
        .onChange(of: s.placeTick) { _, v in if v > 0 { Haptics.impactLight() } }
        .onChange(of: s.clearTick) { _, v in if v > 0 { Haptics.impactMedium() } }
        .onChange(of: s.bigTick) { _, v in if v > 0 { Haptics.impactHeavy() } }
        .onChange(of: s.invalidTick) { _, v in if v > 0 { Haptics.warning() } }
        .onChange(of: s.feverTick) { _, v in if v > 0 { Haptics.success() } }
        .onChange(of: s.milestoneTick) { _, v in if v > 0 { Haptics.success() } }
        .onChange(of: s.gemTick) { _, v in if v > 0 { Haptics.impactLight() } }
    }
}

// MARK: - Scene view

/** The SpriteKit-style board, drawn every frame from the scene (in pixels: the canvas is scaled by 1/scale). */
private struct TileSceneView: View {
    let session: TileBurstSession
    @Environment(\.displayScale) private var scale
    @State private var loop = GameLoop()
    @GestureState private var pressing = false

    var body: some View {
        let scene = session.scene!
        GeometryReader { geo in
            let s = scale
            let _ = scene.layout(geo.size.width * s, geo.size.height * s, (geo.safeAreaInsets.top + 176) * s,
                                 (geo.safeAreaInsets.bottom + 14) * s, s)
            ZStack(alignment: .topLeading) {
                if let bg = scene.backgroundSprite {
                    bg.image(scale: s)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                TileSceneCanvas(scene: scene, scale: s)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { v in
                        let p = CGPoint(x: v.location.x * s, y: v.location.y * s)
                        if !scene.touchActive {
                            scene.touchActive = true
                            scene.began(CGPoint(x: v.startLocation.x * s, y: v.startLocation.y * s))
                            if v.location != v.startLocation { scene.moved(p) }
                        } else {
                            scene.moved(p)
                        }
                    }
                    .onEnded { _ in
                        if scene.touchActive {
                            scene.touchActive = false
                            scene.ended()
                        }
                    }
            )
            .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .global).origin }) { scene.globalOrigin = $0 }
        }
        .ignoresSafeArea()
        .onChange(of: pressing) { _, now in
            // A cancelled touch (system gesture, call) never reaches onEnded.
            if !now && scene.touchActive {
                scene.touchActive = false
                scene.ended()
            }
        }
        .onAppear { run(scene) }
        .onChange(of: ObjectIdentifier(session)) { _, _ in run(session.scene) }
        .onDisappear {
            loop.stop()
            loop.onTick = nil
        }
    }

    private func run(_ scene: TileScene) {
        loop.onTick = { [weak scene] dt in scene?.tick(CGFloat(dt)) }
        loop.start()
    }
}

/// Only this view reads the frame counter, so a tick redraws the canvas and nothing else.
private struct TileSceneCanvas: View {
    let scene: TileScene
    let scale: CGFloat

    var body: some View {
        let tick = scene.frame
        Canvas { ctx, _ in
            _ = tick
            var g = ctx
            g.scaleBy(x: 1 / scale, y: 1 / scale)
            scene.draw(g)
        }
    }
}

// MARK: - HUD

private struct TopBar: View {
    let session: TileBurstSession
    let levelID: Int
    let dim: Double
    let onBack: () -> Void

    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if session.phase == .Ready {
                    GameBackButton(onClick: onBack)
                } else {
                    GameIconButton(Icons.Rounded.Pause, onClick: onBack)
                }
                Group {
                    switch session.mode {
                    case .Adventure:
                        VStack(spacing: 3) {
                            Text("Level \(levelID)").font(rounded(19, FontWeight.ExtraBold)).foregroundStyle(Color.white).lineLimit(1)
                            if let level = session.level { TierChip(level.tier.title, tierIcon(level.tier), tierColor(level.tier, lab)) }
                        }
                    case .Classic:
                        HStack(spacing: 6) {
                            Icon(Icons.Rounded.EmojiEvents, tint: lab.sun, size: 20)
                            Text(tileGrouped(session.best)).font(rounded(19, FontWeight.ExtraBold)).foregroundStyle(Color.white)
                        }
                    case .Daily:
                        HStack(spacing: 6) {
                            Icon(Icons.Rounded.CalendarMonth, tint: hex(0x7FE3FF), size: 20)
                            Text("Daily").font(rounded(19, FontWeight.ExtraBold)).foregroundStyle(Color.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .opacity(dim)
                CoinPill(TileBank.coins) { TileBank.earn($0) }
                    .opacity(dim)
            }
            VStack(spacing: 8) {
                ScoreText(session: session)
                if session.mode == .Adventure, let level = session.level {
                    HStack(spacing: 10) {
                        ForEach(Array(level.goals.enumerated()), id: \.offset) { index, goal in
                            GoalChip(goal: goal, remaining: index < session.remaining.count ? session.remaining[index] : 0,
                                     bump: index < session.goalBumps.count ? session.goalBumps[index] : 0)
                                .onGeometryChange(for: CGPoint.self, of: { g in
                                    let f = g.frame(in: .global)
                                    return CGPoint(x: f.midX, y: f.midY)
                                }) { session.scene.setGoalTarget(index, $0) }
                        }
                        Spacer(minLength: 0)
                        let c = session.rounds <= level.par ? Color.white : lab.sun
                        HStack(spacing: 4) {
                            Icon(Icons.Rounded.Layers, tint: c, size: 15)
                            Text("\(session.rounds)/\(level.par)").font(rounded(13, FontWeight.ExtraBold)).foregroundStyle(c)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                } else {
                    BestBar(session: session)
                }
                ZStack(alignment: .topLeading) {
                    if session.combo >= 2 {
                        ComboPill(combo: session.combo, graceLeft: session.graceLeft, fever: session.fever)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .topLeading)
                .animation(labSpring(0.3, 0.7), value: session.combo >= 2)
            }
            .opacity(dim)
        }
    }
}

private struct ScoreText: View {
    let session: TileBurstSession

    var body: some View {
        CountingText(value: session.score, format: tileGrouped)
            .animation(tween(350), value: session.score)
            .font(rounded(session.mode == .Adventure ? 40 : 54, FontWeight.Black))
            .foregroundStyle(Color.white)
            .shadow(color: hex(0x1A1150, 0.6), radius: 0, x: 0, y: 4)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .scaleEffect(session.fever ? 1.06 : 1)
            .animation(labSpring(0.3, 0.6), value: session.fever)
    }
}

private struct BestBar: View {
    let session: TileBurstSession

    var body: some View {
        let lab = Lab.colors
        let daily = session.mode == .Daily
        let passed = daily ? session.reachedTarget : session.passedBest
        let label = daily ? "Target \(tileGrouped(session.dailyTarget))" : (session.best == 0 ? "Set your first best!" : "Best \(tileGrouped(session.best))")
        let p = CGFloat(session.bestProgress)
        VStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(LinearGradient(colors: passed ? [hex(0xFFD35A), hex(0xFF8A3D)] : [hex(0x7FE3FF), hex(0x9F8CFF)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * max(0.03, p))
                        .animation(tween(300), value: p)
                }
            }
            .frame(height: 8)
            HStack(spacing: 4) {
                if passed { Icon(Icons.Rounded.Verified, tint: lab.sun, size: 13) }
                Text(passed ? "Beat it!" : label).font(rounded(12, FontWeight.ExtraBold)).foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}

/// The coin counter, counting up when coins arrive.
private struct CoinCounter: View, Animatable {
    var value: Double
    let onPlus: (() -> Void)?

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        GameCounter(Icons.Rounded.MonetizationOn, tileGrouped(Int(value.rounded())), GameColors.gold, height: 38, onPlus: onPlus)
    }
}

struct CoinPill: View {
    let coins: Int
    let onEarn: (Int) -> Void

    init(_ coins: Int, _ onEarn: @escaping (Int) -> Void) {
        self.coins = coins
        self.onEarn = onEarn
    }

    var body: some View {
        CoinCounter(value: Double(coins), onPlus: { offerCoins(50, onEarn) })
            .animation(tween(400), value: coins)
    }
}

private struct ComboPill: View {
    let combo: Int
    let graceLeft: Int
    let fever: Bool

    var body: some View {
        let accent = fever ? hex(0xFF8A3D) : hex(0x7B5CFF)
        HStack(spacing: 8) {
            Text("Combo ×\(combo)").font(rounded(15, FontWeight.Black)).foregroundStyle(Color.white)
            HStack(spacing: 3) {
                ForEach(0..<TileBoard.COMBO_GRACE, id: \.self) { k in
                    Circle().fill(Color.white.opacity(k < graceLeft ? 1 : 0.25)).frame(width: 6, height: 6)
                }
            }
            if fever {
                Text("×2").font(rounded(13, FontWeight.Black)).foregroundStyle(Color.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(hex(0xFF8A3D)))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(LinearGradient(colors: fever ? [hex(0xFFB020), hex(0xE0561B)] : [hex(0x7B5CFF), hex(0x4B3BC4)],
                                                  startPoint: .leading, endPoint: .trailing)))
        .labShadow(accent.copy(alpha: 0.6), 8, 0, 15)
    }
}

private struct GoalChip: View {
    let goal: TileGoal
    let remaining: Int
    let bump: Int
    @State private var pop: CGFloat = 1

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                GoalIcon(goal: goal, size: 30)
                if remaining == 0 {
                    Icon(Icons.Rounded.CheckCircle, tint: hex(0x2FBF63), size: 14)
                        .background(Circle().fill(Color.white))
                        .clipShape(Circle())
                        .offset(x: 4, y: 4)
                }
            }
            Text(goal.kind == .Score ? tileGrouped(remaining) : "\(remaining)")
                .font(rounded(17, FontWeight.Black))
                .foregroundStyle(Color.white.opacity(remaining == 0 ? 0.5 : 1))
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Capsule().fill(Color.white.opacity(0.16)))
        .scaleEffect(pop)
        .onChange(of: bump) { _, b in
            if b == 0 { return }
            withAnimation(labSpring(0.18, 0.5)) { pop = 1.15 } completion: {
                withAnimation(labSpring(0.3, 0.7)) { pop = 1 }
            }
        }
    }
}

// MARK: - Cards

private struct TileCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var appear = false

    var body: some View {
        let a: Double = appear ? 1 : 0
        ZStack {
            Color.black.opacity(0.45 * a)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(spacing: 16) { content() }
                .padding(24)
                .frame(maxWidth: 460)
                .gamePopup(32, TileBurstModule.info.colors)
                .scaleEffect(0.85 + 0.15 * a)
                .opacity(a)
                .padding(.horizontal, 24)
        }
        .onAppear { withAnimation(labSpring(0.5, 0.75)) { appear = true } }
    }
}

private struct SecondaryButton: View {
    let title: String
    let icon: ImageVector
    let onClick: () -> Void

    var body: some View {
        GameButton(title, fill: true, icon: icon, colors: GameColors.slate(), height: 52, fontSize: 16, onClick: onClick)
            .frame(maxWidth: .infinity)
    }
}

private struct IntroCard: View {
    let session: TileBurstSession
    let level: TileLevel?
    let onMode: (TileBurstSession.Mode) -> Void
    let onStart: () -> Void
    let onHowTo: () -> Void

    var body: some View {
        let lab = Lab.colors
        let info = TileBurstModule.info
        VStack(spacing: 16) {
            TileBurstArtwork(compact: true)
                .frame(width: 150, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .floating(2.5, periodMs: 1200)
            HStack(spacing: 6) {
                ForEach(TileBurstSession.Mode.entries, id: \.self) { mode in
                    let selected = session.mode == mode
                    let icon: ImageVector = {
                        switch mode {
                        case .Adventure: return Icons.Rounded.Map
                        case .Classic: return Icons.Rounded.AllInclusive
                        case .Daily: return Icons.Rounded.CalendarMonth
                        }
                    }()
                    let face = selected ? info.colors : GameColors.slate()
                    let ink = GameColors.ink(face)
                    GameKey(colors: face, corner: 20, depth: 4, fill: true, onClick: { onMode(mode) }) {
                        HStack(spacing: 4) {
                            Icon(icon, tint: ink, size: 15)
                            if selected {
                                Text(mode.title).font(gameTextStyle(13, (face.last ?? .black).mix(.black, 0.45).copy(alpha: 0.6)))
                                    .foregroundStyle(ink).lineLimit(1)
                            } else {
                                Text(mode.title).font(rounded(13, FontWeight.ExtraBold)).foregroundStyle(ink).lineLimit(1)
                            }
                        }
                        .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
            }
            switch session.mode {
            case .Adventure:
                if let level {
                    VStack(spacing: 6) {
                        TierChip(level.tier.title, tierIcon(level.tier), tierColor(level.tier, lab))
                        Text("Level \(level.id)").font(rounded(30, FontWeight.ExtraBold)).foregroundStyle(lab.ink)
                        Text("\(TileArt.worldName(level.world)) · 3★ in \(level.par) trays").font(rounded(14, FontWeight.SemiBold)).foregroundStyle(lab.inkSecondary)
                    }
                    VStack(spacing: 8) {
                        ForEach(Array(level.goals.enumerated()), id: \.offset) { index, goal in
                            HStack(spacing: 12) {
                                GoalIcon(goal: goal, size: 30)
                                Text(goalText(goal, index < session.board.goalTotals.count ? session.board.goalTotals[index] : 0))
                                    .font(rounded(15, FontWeight.Bold)).foregroundStyle(lab.ink)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(lab.surfaceAlt.copy(alpha: 0.7)))
                        }
                    }
                    if let tip = level.tip {
                        HStack(alignment: .top, spacing: 8) {
                            Icon(Icons.Rounded.AutoAwesome, tint: lab.ink, size: 16)
                            Text(tip).font(rounded(14, FontWeight.Bold)).foregroundStyle(lab.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(lab.sun.copy(alpha: 0.22)))
                    }
                }
            case .Classic:
                VStack(spacing: 8) {
                    Text("Classic").font(rounded(30, FontWeight.ExtraBold)).foregroundStyle(lab.ink)
                    HStack(spacing: 6) {
                        Icon(Icons.Rounded.EmojiEvents, tint: lab.sun, size: 18)
                        Text("Best \(tileGrouped(TileRecords.classicBest))").font(rounded(17, FontWeight.ExtraBold)).foregroundStyle(lab.ink)
                    }
                    Text("Endless board. Clear rows and columns, keep your combo alive, and beat your best.")
                        .font(rounded(14, FontWeight.SemiBold)).foregroundStyle(lab.inkSecondary).multilineTextAlignment(.center)
                }
            case .Daily:
                VStack(spacing: 8) {
                    Text("Daily challenge").font(rounded(28, FontWeight.ExtraBold)).foregroundStyle(lab.ink)
                    Text(IntroCard.dateText()).font(rounded(14, FontWeight.SemiBold)).foregroundStyle(lab.inkSecondary)
                    HStack(spacing: 12) {
                        CardStat(title: "Target", value: tileGrouped(session.dailyTarget), icon: Icons.Rounded.TrackChanges)
                        CardStat(title: "Streak", value: "\(TileRecords.dailyStreak)", icon: Icons.Rounded.LocalFireDepartment)
                        CardStat(title: "Today", value: TileRecords.isDailyDone(session.day) ? "Done" : "—", icon: Icons.Rounded.Verified)
                    }
                    Text("Everyone gets the same pieces today. Reach the target to grow your streak.")
                        .font(rounded(13, FontWeight.SemiBold)).foregroundStyle(lab.inkSecondary).multilineTextAlignment(.center)
                }
            }
            HStack(spacing: 10) {
                LabPrimaryButton("Play", icon: Icons.Rounded.PlayArrow, colors: info.colors, height: 58, onClick: onStart)
                GameIconButton(Icons.Rounded.QuestionMark, colors: GameColors.slate(), size: 54, iconSize: 22, onClick: onHowTo)
            }
        }
        .padding(22)
        .frame(maxWidth: 460)
        .gamePopup(32, info.colors)
        .padding(.horizontal, 22)
    }

    /// Kotlin `SimpleDateFormat("EEEE, d MMMM yyyy", Locale.getDefault())`.
    static func dateText() -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: Date())
    }
}

private struct CardStat: View {
    let title: String
    let value: String
    let icon: ImageVector

    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 3) {
            Icon(icon, tint: TileBurstModule.info.first, size: 16)
            Text(value).font(rounded(16, FontWeight.ExtraBold)).foregroundStyle(lab.ink).lineLimit(1)
            Text(title.uppercased()).font(rounded(9, FontWeight.ExtraBold, tracking: 0.6)).foregroundStyle(lab.inkSecondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(lab.surfaceAlt.copy(alpha: 0.7)))
    }
}

private struct ReviveCard: View {
    let session: TileBurstSession

    var body: some View {
        let lab = Lab.colors
        let info = TileBurstModule.info
        TileCard {
            Icon(Icons.Rounded.ViewModule, tint: info.first, size: 54)
            VStack(spacing: 6) {
                Text("Out of space!").font(gameTextStyle(30)).foregroundStyle(lab.ink)
                Text("Revive clears a 3×3 area and deals you fresh pieces.")
                    .font(rounded(15, FontWeight.SemiBold)).foregroundStyle(lab.inkSecondary).multilineTextAlignment(.center)
            }
            LabPrimaryButton("Revive · \(TileBank.REVIVE_COST)", icon: Icons.Rounded.Undo, colors: info.colors, height: 58, enabled: session.canRevive) {
                Haptics.cta()
                session.revive()
            }
            if TileBank.coins < TileBank.REVIVE_COST {
                HStack(spacing: 8) {
                    Text("You have \(TileBank.coins) coins.").font(rounded(13, FontWeight.SemiBold)).foregroundStyle(lab.inkSecondary)
                    Text("Get more").font(rounded(13, FontWeight.ExtraBold)).foregroundStyle(lab.ok)
                        .pressable(0.9) { offerCoins(150) { TileBank.earn($0) } }
                }
            }
            SecondaryButton(title: "No thanks", icon: Icons.Rounded.Close) { session.declineRevive() }
        }
    }
}

private struct LossCard: View {
    let session: TileBurstSession
    let onRetry: () -> Void
    let onLevels: () -> Void

    var body: some View {
        let lab = Lab.colors
        let info = TileBurstModule.info
        TileCard {
            Icon(Icons.Rounded.ViewModule, tint: lab.danger, size: 54)
            VStack(spacing: 6) {
                Text("No space left").font(gameTextStyle(30)).foregroundStyle(lab.ink)
                Text("So close! Keep the middle open for the big pieces.")
                    .font(rounded(15, FontWeight.SemiBold)).foregroundStyle(lab.inkSecondary).multilineTextAlignment(.center)
            }
            if let level = session.level {
                HStack(spacing: 10) {
                    ForEach(Array(level.goals.enumerated()), id: \.offset) { index, goal in
                        GoalChip(goal: goal, remaining: index < session.remaining.count ? session.remaining[index] : 0, bump: 0)
                            .padding(4)
                            .background(Capsule().fill(hex(0x2E2A8C)))
                    }
                }
            }
            LabPrimaryButton("Retry", icon: Icons.Rounded.Replay, colors: info.colors, height: 58, onClick: onRetry)
            SecondaryButton(title: "Levels", icon: Icons.Rounded.GridView, onClick: onLevels)
        }
    }
}

private struct ScoreCard: View {
    let session: TileBurstSession
    let onAgain: () -> Void
    let onModes: () -> Void
    @State private var target = 0

    var body: some View {
        let lab = Lab.colors
        let info = TileBurstModule.info
        let daily = session.mode == .Daily
        ZStack {
            TileCard {
                Icon(session.isNewBest ? Icons.Rounded.EmojiEvents : Icons.Rounded.Flag, tint: session.isNewBest ? lab.sun : info.first, size: 54)
                Text(session.isNewBest ? "New best!" : (daily ? "Daily done" : "Game over"))
                    .font(rounded(30, FontWeight.ExtraBold)).foregroundStyle(lab.ink)
                CountingText(value: target, format: tileGrouped)
                    .font(rounded(52, FontWeight.Black))
                    .foregroundStyle(info.gradient)
                    .lineLimit(1)
                HStack(spacing: 0) {
                    CardStat(title: daily ? "Target" : "Best", value: tileGrouped(daily ? session.dailyTarget : max(session.score, TileRecords.classicBest)),
                             icon: daily ? Icons.Rounded.TrackChanges : Icons.Rounded.EmojiEvents)
                    CardStat(title: "Best combo", value: "×\(session.board.bestCombo)", icon: Icons.Rounded.Bolt)
                    CardStat(title: "Coins", value: "+\(session.coinsEarned)", icon: Icons.Rounded.MonetizationOn)
                }
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(lab.surfaceAlt.copy(alpha: 0.6)))
                if daily {
                    HStack(spacing: 6) {
                        Icon(session.reachedTarget ? Icons.Rounded.LocalFireDepartment : Icons.Rounded.TrackChanges,
                             tint: session.reachedTarget ? hex(0xFF8A3D) : lab.inkSecondary, size: 16)
                        Text(session.reachedTarget ? "Target reached · streak \(TileRecords.dailyStreak)" : "Target missed, try again!")
                            .font(rounded(14, FontWeight.Bold)).foregroundStyle(session.reachedTarget ? hex(0xFF8A3D) : lab.inkSecondary)
                    }
                }
                LabPrimaryButton("Play again", icon: Icons.Rounded.Replay, colors: info.colors, height: 58, onClick: onAgain)
                SecondaryButton(title: "Modes", icon: Icons.Rounded.GridView, onClick: onModes)
            }
            if session.isNewBest { ConfettiView().allowsHitTesting(false) }
        }
        .onAppear { withAnimation(tween(720)) { target = session.score } }
    }
}

private struct PauseSheet: View {
    let confirmQuit: Bool
    let onResume: () -> Void
    let onRestart: () -> Void
    let onQuit: () -> Void
    let onKeep: () -> Void
    let onLeave: () -> Void
    @State private var appear = false

    var body: some View {
        let lab = Lab.colors
        let info = TileBurstModule.info
        let a: Double = appear ? 1 : 0
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.45 * a)
                    .contentShape(Rectangle())
                    .onTapGesture { onResume() }
                VStack(spacing: 14) {
                    Capsule().fill(lab.gridLine).frame(width: 40, height: 5)
                    if !confirmQuit {
                        Text("Paused").font(gameTextStyle(28)).foregroundStyle(lab.ink).padding(.top, 8)
                        LabPrimaryButton("Resume", icon: Icons.Rounded.PlayArrow, colors: info.colors, height: 58, onClick: onResume)
                        HStack(spacing: 12) {
                            SecondaryButton(title: "Restart", icon: Icons.Rounded.Replay, onClick: onRestart)
                            SecondaryButton(title: "Quit", icon: Icons.Rounded.Close, onClick: onQuit)
                        }
                    } else {
                        ZStack {
                            Circle().fill(LinearGradient(colors: [hex(0xFF5A6E), hex(0xD7263D)], startPoint: .top, endPoint: .bottom))
                            Icon(Icons.Rounded.Close, tint: Color.white, size: 26)
                        }
                        .frame(width: 56, height: 56)
                        .padding(.top, 8)
                        Text("Leave this game?").font(rounded(21, FontWeight.Black)).foregroundStyle(lab.ink)
                        Text("This board won't be saved.").font(rounded(15, FontWeight.SemiBold)).foregroundStyle(lab.ink2)
                        SecondaryButton(title: "Keep playing", icon: Icons.Rounded.PlayArrow, onClick: onKeep)
                        LabPrimaryButton("Leave", colors: GameColors.red, height: 52, onClick: onLeave)
                    }
                    Spacer().frame(width: 1, height: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 16 + geo.safeAreaInsets.bottom)
                .frame(maxWidth: .infinity)
                .gamePopup(32, info.colors)
                .contentShape(Rectangle())
                .onTapGesture {}
                .offset(y: appear ? 0 : geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(labSpring(0.5, 0.86)) { appear = true } }
    }
}
