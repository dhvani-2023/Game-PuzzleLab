import SwiftUI
import GameKit

/// Holds the current session without making SwiftUI re-create it (Kotlin `remember { mutableStateOf(...) }`).
@MainActor
private final class ArrowPlayBox {
    var session: ArrowJamSession?
    var levelID = 1
}

/// Arrow Jam's play screen: hearts, combo and progress on top, the board, and the tool dock.
struct ArrowJamPlay: View {
    let startLevel: Int
    let mode: ArrowJamSession.Mode

    init(_ startLevel: Int, _ mode: ArrowJamSession.Mode) {
        self.startLevel = startLevel
        self.mode = mode
    }

    @Environment(AppState.self) private var app
    @State private var box = ArrowPlayBox()
    @State private var generation = 0
    @State private var themeID = Prefs.string("arrowjam.theme") ?? "auto"
    @State private var showGrid = Prefs.bool("arrowjam.grid")
    @State private var fitRequest = 0
    @State private var showWin = false
    @State private var showThemes = false
    @State private var showHowTo = false
    @State private var dailyStreak = 0
    @State private var tipVisible = true

    private var module: ArrowJamModule { ArrowJamModule.shared }
    private var info: GameInfo { module.info }
    private var pack: ArrowLevelPack { mode == .Daily ? module.dailyPack : module.pack }
    private var progress: GameProgress { app.store.progress(info.id) }

    private func makeSession(_ id: Int, _ saved: String?) -> ArrowJamSession {
        ArrowJamSession(mode, pack.level(id) ?? pack.levels[0], Lab.reduceMotion, saved)
    }

    private var session: ArrowJamSession {
        if let s = box.session { return s }
        let id = pack.level(startLevel) == nil ? 1 : startLevel
        box.levelID = id
        let s = makeSession(id, mode == .Adventure ? progress.savedState(id, pack.version) : nil)
        box.session = s
        return s
    }

    private var levelID: Int {
        _ = session
        return box.levelID
    }

    private func save() {
        if mode != .Adventure { return }
        let s = session
        progress.saveState(s.phase == .Playing ? s.snapshot : nil, levelID, pack.version)
    }

    private func reload() {
        showWin = false
        tipVisible = true
        box.session?.dispose()
        box.session = makeSession(box.levelID, nil)
        generation += 1
    }

    private func leave() {
        save()
        if mode == .Adventure { app.router.backToLevels(info.id) } else { app.router.pop() }
    }

    private func next() {
        if mode != .Adventure || pack.level(levelID + 1) == nil { leave(); return }
        box.levelID += 1
        reload()
    }

    private func notEnoughCoins() {
        ArrowSound.play(.Bump)
        if adUnlocksEnabled { offerCoins(100) { ArrowBank.earn($0) } }
    }

    var body: some View {
        let s = session
        let lab = Lab.colors
        let dark = lab.isDark
        let reduce = Lab.reduceMotion
        let theme = ArrowTheme.resolve(themeID, dark)
        let playing = s.phase == .Playing
        ZStack {
            LinearGradient(colors: [theme.top.color, theme.bottom.color], startPoint: .top, endPoint: .bottom)
                .animation(tween(350), value: theme.id)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                // Top bar
                HStack(spacing: 0) {
                    GameBackButton { leave() }
                    VStack(spacing: 1) {
                        Text(mode == .Daily ? "Daily" : "Level \(levelID)")
                            .font(rounded(20, FontWeight.Black)).foregroundStyle(theme.hud.color)
                        Text("\((s.level.pic ?? "Picture").uppercased()) · \(s.total) ARROWS")
                            .font(rounded(10, FontWeight.ExtraBold, tracking: 1.1)).foregroundStyle(theme.hud.copy(alpha: 0.6).color)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    ArrowHudButton(Icons.Rounded.Palette) { showThemes = true }
                }
                // Hearts, combo, coins
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        ForEach(0..<ArrowJamSession.MAX_HEARTS, id: \.self) { i in ArrowHeart(i < s.hearts) }
                    }
                    ZStack {
                        if s.combo >= 2 && playing {
                            ArrowComboPill(session: s)
                                .transition(.asymmetric(insertion: .scale.combined(with: .opacity).animation(labSpring(0.42, 0.6)),
                                                        removal: .scale.combined(with: .opacity).animation(tween(300))))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .animation(labSpring(0.42, 0.6), value: s.combo >= 2 && playing)
                    ArrowCoinPill()
                }
                .frame(height: 36)
                // Progress
                ArrowProgressBar(fraction: CGFloat(s.cleared) / CGFloat(max(s.total, 1)), track: theme.hud.copy(alpha: 0.12).color)
                if let tip = s.level.tip, tipVisible && playing {
                    HStack(spacing: 8) {
                        Icon(Icons.Rounded.Lightbulb, tint: lab.sun, size: 18)
                        Text(tip).font(rounded(14, FontWeight.Bold)).foregroundStyle(theme.hud.color)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .circular).fill(theme.glass.color))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .circular).strokeBorder(theme.stroke.color, lineWidth: 1))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                // Board
                ArrowBoardView(s, theme, showGrid, fitRequest)
                    .id(generation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        if s.hammerArmed {
                            HStack(spacing: 6) {
                                Icon(Icons.Rounded.Gavel, tint: .white, size: 16)
                                Text("Tap any arrow to smash it").font(rounded(14, FontWeight.ExtraBold)).foregroundStyle(Color.white)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Capsule().fill(hex(0x2FB9A0)))
                            .labShadow(Color.black.opacity(0.2), 8, 4, 18)
                            .transition(.scale.combined(with: .opacity))
                            .allowsHitTesting(false)
                        }
                    }
                    .animation(tween(250), value: s.hammerArmed)
                // Tool dock
                HStack(spacing: 18) {
                    ArrowToolButton(Icons.Rounded.Lightbulb, "Hint", s.hintPriceLabel, ArrowRecords.freeHintsLeft == 0, hex(0xFFB020), theme, false, playing) {
                        if !s.useHint() { notEnoughCoins() }
                    }
                    ArrowToolButton(Icons.Rounded.Gavel, s.hammerArmed ? "Cancel" : "Hammer",
                                    s.hammerArmed ? nil : (s.hammerIsFree ? "1" : "\(ArrowBank.HAMMER_COST)"), !s.hammerIsFree,
                                    hex(0x2FB9A0), theme, s.hammerArmed, playing) {
                        if !s.toggleHammer() { notEnoughCoins() }
                    }
                    ArrowToolButton(Icons.Rounded.Tag, "Grid", nil, false, theme.hud.color, theme, showGrid, playing) {
                        showGrid.toggle()
                        Prefs.putBool("arrowjam.grid", showGrid)
                    }
                    ArrowToolButton(Icons.Rounded.FitScreen, "Fit", nil, false, hex(0x6E5BFF), theme, false, playing) { fitRequest += 1 }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .animation(tween(300), value: tipVisible && playing && s.level.tip != nil)

            if s.phase == .Lost {
                ArrowLoseCard(
                    canSkip: mode == .Adventure && ArrowRecords.fails(levelID) >= 3,
                    onRevive: { if !s.revive() { notEnoughCoins() } },
                    onRetry: {
                        if mode == .Adventure { progress.saveState(nil, levelID, pack.version) }
                        reload()
                    },
                    onSkip: {
                        if !ArrowBank.spend(ArrowBank.SKIP_COST) {
                            notEnoughCoins()
                        } else {
                            app.store.recordSolve(info.id, levelID, s.elapsedSeconds, 2)
                            ArrowRecords.clearFails(levelID)
                            next()
                        }
                    },
                    onLevels: { leave() }
                )
                .zIndex(1)
            }
            if showWin {
                ArrowWinCard(session: s, isDaily: mode == .Daily, dailyStreak: dailyStreak, isLastLevel: levelID >= pack.count,
                             onNext: { next() },
                             onReplay: {
                                 withAnimation(tween(250)) { showWin = false }
                                 s.playReplay()
                                 Task { @MainActor in
                                     try? await Task.sleep(nanoseconds: 400_000_000)
                                     while s.replaying { try? await Task.sleep(nanoseconds: 150_000_000) }
                                     if box.session === s { withAnimation(tween(350)) { showWin = true } }
                                 }
                             },
                             onLevels: { leave() })
                    .transition(.asymmetric(insertion: .opacity.animation(tween(350)), removal: .opacity.animation(tween(250))))
                    .zIndex(2)
            }
            if showThemes {
                ArrowThemeSheet(selection: themeID, dark: dark, onPick: { id in
                    themeID = id
                    Prefs.putString("arrowjam.theme", id)
                }, onDone: { showThemes = false })
                .zIndex(3)
            }
            if showHowTo {
                HowToPlaySheet(module) { showHowTo = false }
                    .zIndex(4)
            }
        }
        .onAppear {
            ArrowSound.warmUp()
            ArrowBank.load()
            if mode == .Adventure { app.store.markPlayed(info.id) }
            if session.cleared >= 3 { tipVisible = false }
            save()
        }
        .onDisappear {
            save()
            box.session?.dispose()
        }
        .task {
            let key = "howToPlay.\(info.id).seen"
            if !Prefs.bool(key) {
                Prefs.putBool(key, true)
                try? await Task.sleep(nanoseconds: 600_000_000)
                if !Task.isCancelled { showHowTo = true }
            }
        }
        // On the first levels, a free hint appears if the player waits without clearing anything.
        .task(id: generation) {
            if mode != .Adventure || levelID > 3 { return }
            var lastCleared = -1
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                let cur = session
                if cur.phase != .Playing || showHowTo { continue }
                if cur.cleared == lastCleared && (cur.hint?.second ?? 0) < nowSeconds(), let h = cur.board.bestHint() { cur.showHint(h) }
                lastCleared = cur.cleared
            }
        }
        .onChange(of: "\(generation)-\(s.cleared)") {
            if session.cleared >= 3 { tipVisible = false }
            save()
        }
        .onChange(of: AppLifecycle.pauses) { save() }
        .task(id: "\(generation)-\(s.phase == .Won)") {
            let cur = session
            guard cur.phase == .Won else { return }
            ArrowBank.earn(cur.coinsEarned)
            if mode == .Adventure {
                app.store.recordSolve(info.id, levelID, cur.elapsedSeconds, cur.heartsLost)
                ArrowRecords.clearFails(levelID)
            } else {
                dailyStreak = ArrowRecords.markDailyDone()
                if dailyStreak > 0 && dailyStreak % 7 == 0 { ArrowBank.earn(100) }
            }
            Haptics.success()
            try? await Task.sleep(nanoseconds: reduce ? 150_000_000 : 550_000_000)
            if Task.isCancelled { return }
            withAnimation(tween(350)) { showWin = true }
        }
        .onChange(of: s.exitTick) { _, n in if n > 0 { Haptics.impactLight() } }
        .onChange(of: s.bumpTick) { _, n in if n > 0 { Haptics.warning() } }
        .onChange(of: s.hammerTick) { _, n in if n > 0 { Haptics.impactHeavy() } }
        .onChange(of: s.hintTick) { _, n in if n > 0 { Haptics.selection() } }
    }
}

// MARK: - HUD

private struct ArrowHudButton: View {
    let icon: ImageVector
    let onClick: () -> Void

    init(_ icon: ImageVector, onClick: @escaping () -> Void) {
        self.icon = icon
        self.onClick = onClick
    }

    var body: some View {
        GameIconButton(icon, colors: GameColors.slate(), size: 46, iconSize: 21) {
            ArrowSound.play(.Tap)
            onClick()
        }
    }
}

private struct ArrowHeart: View {
    let full: Bool

    init(_ full: Bool) { self.full = full }

    var body: some View {
        Icon(full ? Icons.Rounded.Favorite : Icons.Rounded.HeartBroken, tint: full ? hex(0xFF4D6A) : hex(0x888888, 0.45), size: 26)
            .background {
                if full { Color.clear.labShadow(hex(0xFF3B5C, 0.35), 4, 2, circle: true) }
            }
            .scaleEffect(full ? 1 : 0.86)
            .animation(labSpring(0.42, 0.6), value: full)
    }
}

private struct ArrowProgressBar: View {
    let fraction: CGFloat
    let track: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(LinearGradient(colors: [hex(0x46D39A), hex(0x2FB9A0)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * max(0.02, fraction))
            }
        }
        .frame(height: 8)
        .animation(labSpring(0.6, 0.88), value: fraction)
    }
}

private struct ArrowComboPill: View {
    let session: ArrowJamSession

    var body: some View {
        let combo = session.combo
        HStack(spacing: 6) {
            TimelineView(.animation) { timeline in
                let tick = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    _ = tick
                    let left = CGFloat(session.comboTimeLeft(nowSeconds()))
                    let w: CGFloat = 3
                    let r = min(size.width, size.height) / 2 - w / 2
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(hex(0xFFC93A, 0.25)), lineWidth: w)
                    var arc = Path()
                    arc.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(left)), clockwise: false)
                    ctx.stroke(arc, with: .color(hex(0xFFC93A)), style: StrokeStyle(lineWidth: w, lineCap: .round))
                }
            }
            .frame(width: 16, height: 16)
            Text("Combo ×\(combo)")
                .font(rounded(15, FontWeight.Black))
                .foregroundStyle(LinearGradient(colors: [hex(0xFFC93A), hex(0xFF7A45)], startPoint: .top, endPoint: .bottom))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(hex(0x231C52, 0.85)))
        .overlay(Capsule().strokeBorder(hex(0xFFC93A, 0.4), lineWidth: 1))
        .scaleEffect(1 + min(0.12, CGFloat(combo) * 0.01))
        .animation(labSpring(0.42, 0.6), value: combo)
    }
}

/// The coin counter; the number counts to its new value (Compose `animateIntAsState(tween(400))`).
private struct ArrowCoinPill: View {
    var body: some View {
        ArrowCountingCounter(value: Double(max(0, ArrowBank.coins)))
            .animation(tween(400), value: ArrowBank.coins)
    }
}

private struct ArrowCountingCounter: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        GameCounter(Icons.Rounded.MonetizationOn, Int(value.rounded()).grouped, GameColors.gold, height: 36,
                    onPlus: adUnlocksEnabled ? { offerCoins(50) { ArrowBank.earn($0) } } : nil)
    }
}

private struct ArrowToolButton: View {
    let icon: ImageVector
    let label: String
    let badge: String?
    let badgeIsPrice: Bool
    let tint: Color
    let theme: ArrowTheme
    let active: Bool
    let enabled: Bool
    let onClick: () -> Void

    init(_ icon: ImageVector, _ label: String, _ badge: String?, _ badgeIsPrice: Bool, _ tint: Color, _ theme: ArrowTheme, _ active: Bool,
         _ enabled: Bool, onClick: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.badge = badge
        self.badgeIsPrice = badgeIsPrice
        self.tint = tint
        self.theme = theme
        self.active = active
        self.enabled = enabled
        self.onClick = onClick
    }

    var body: some View {
        let face = active ? GameColors.red : [tint.mix(.white, 0.25), tint.mix(.black, 0.2)]
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                GameIconButton(icon, colors: face, size: 56, iconSize: 26, enabled: enabled) {
                    ArrowSound.play(.Tap)
                    onClick()
                }
                if let badge {
                    GameBadge(badge, colors: badgeIsPrice ? GameColors.gold : GameColors.red, icon: badgeIsPrice ? Icons.Rounded.MonetizationOn : nil)
                        .fixedSize()
                        .offset(x: 10, y: -6)
                        .allowsHitTesting(false)
                }
            }
            Text(label)
                .font(gameTextStyle(11.5, Color.black.opacity(theme.isDark ? 0.4 : 0.08)))
                .foregroundStyle(theme.hud.copy(alpha: 0.85).color)
        }
    }
}

// MARK: - Cards

private struct ArrowDarkCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var appear: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.45 * Double(min(max(appear, 0), 1)))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(spacing: 14) { content() }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .circular)
                        .fill(LinearGradient(colors: [hex(0x2E2272), hex(0x14112E)], startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .circular)
                        .strokeBorder(LinearGradient(colors: [hex(0xFFC93A, 0.9), hex(0xD9762A, 0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                )
                .labShadow(Color.black.opacity(0.45), 30, 14, 32)
                .frame(maxWidth: 460)
                .scaleEffect(0.9 + 0.1 * appear)
                .opacity(Double(min(max(appear, 0), 1)))
                .padding(.horizontal, 20)
        }
        .onAppear { withAnimation(labSpring(0.6, 0.88)) { appear = 1 } }
    }
}

private struct ArrowLoseCard: View {
    let canSkip: Bool
    let onRevive: () -> Void
    let onRetry: () -> Void
    let onSkip: () -> Void
    let onLevels: () -> Void

    var body: some View {
        ArrowDarkCard {
            Icon(Icons.Rounded.HeartBroken, tint: hex(0xFF4D6A), size: 52)
            Text("Out of hearts").font(gameTextStyle(28)).foregroundStyle(Color.white)
            Text("Keep your cleared arrows and get three new hearts, or start the board again.")
                .font(rounded(15, FontWeight.SemiBold)).foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            LabPrimaryButton("Revive · \(ArrowBank.REVIVE_COST)", icon: Icons.Rounded.Favorite, colors: GameColors.red, enabled: true) {
                Haptics.cta()
                onRevive()
            }
            GameButton("Try again", fill: true, colors: [hex(0x625C8E), hex(0x3A3462)], height: 52, fontSize: 17, onClick: onRetry)
                .frame(maxWidth: .infinity)
            if canSkip {
                HStack(spacing: 6) {
                    Icon(Icons.Rounded.FastForward, tint: Color.white.opacity(0.8), size: 16)
                    Text("Skip level · \(ArrowBank.SKIP_COST) coins").font(rounded(16, FontWeight.Bold)).foregroundStyle(Color.white.opacity(0.8))
                }
                .padding(6)
                .pressable(0.95, sound: true, onClick: onSkip)
            }
            Text("Levels").font(rounded(16, FontWeight.Bold)).foregroundStyle(Color.white.opacity(0.8))
                .padding(6)
                .pressable(0.95, sound: true, onClick: onLevels)
        }
    }
}

private struct ArrowWinCard: View {
    let session: ArrowJamSession
    let isDaily: Bool
    let dailyStreak: Int
    let isLastLevel: Bool
    let onNext: () -> Void
    let onReplay: () -> Void
    let onLevels: () -> Void

    @State private var shownStars = 0

    var body: some View {
        let reduce = Lab.reduceMotion
        ZStack {
            ArrowDarkCard {
                Text(isDaily ? "DAILY PICTURE COMPLETE" : "PICTURE COMPLETE")
                    .font(rounded(13, FontWeight.ExtraBold, tracking: 1.6)).foregroundStyle(Lab.colors.sun)
                ClearStage(session.level, !reduce)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                Text(isDaily ? "Daily done!" : "Level \(session.level.id)").font(gameTextStyle(32)).foregroundStyle(Color.white)
                HStack(alignment: .center, spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        let on = i < shownStars
                        Icon(Icons.Rounded.Star, tint: on ? hex(0xFFC93A) : Color.white.opacity(0.15), size: i == 1 ? 50 : 40)
                            .background {
                                if on { Color.clear.labShadow(hex(0xFFB020, 0.6), 10, 0, circle: true) }
                            }
                            .scaleEffect(on ? 1 : 0.7)
                            .animation(labSpring(0.42, 0.6), value: on)
                            .offset(y: i == 1 ? -6 : 0)
                    }
                }
                HStack(spacing: 0) {
                    ArrowWinStat(session.heartsLost == 0 ? "No hearts lost" : "\(session.heartsLost) heart\(session.heartsLost == 1 ? "" : "s") lost",
                                 Icons.Rounded.Favorite, hex(0xFF5C7A))
                    ArrowWinStat("Best combo ×\(max(1, session.bestCombo))", Icons.Rounded.Bolt, hex(0xFFC93A))
                    ArrowWinStat(isDaily ? "Streak \(dailyStreak)" : "+\(session.coinsEarned) coins",
                                 isDaily ? Icons.Rounded.LocalFireDepartment : Icons.Rounded.MonetizationOn, isDaily ? hex(0xFF8A3D) : hex(0x46D39A))
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 20, style: .circular).fill(Color.white.opacity(0.08)))
                LabPrimaryButton(isDaily ? "Done" : (isLastLevel ? "Back to the map" : "Next level")) {
                    Haptics.cta()
                    onNext()
                }
                HStack(spacing: 24) {
                    HStack(spacing: 5) {
                        Icon(Icons.Rounded.PlayCircle, tint: Color.white.opacity(0.8), size: 18)
                        Text("Watch replay").font(rounded(15, FontWeight.Bold)).foregroundStyle(Color.white.opacity(0.8))
                    }
                    .pressable(0.95, sound: true, onClick: onReplay)
                    if !isDaily {
                        HStack(spacing: 5) {
                            Icon(Icons.Rounded.Map, tint: Color.white.opacity(0.8), size: 18)
                            Text("Levels").font(rounded(15, FontWeight.Bold)).foregroundStyle(Color.white.opacity(0.8))
                        }
                        .pressable(0.95, sound: true, onClick: onLevels)
                    }
                }
            }
            if session.stars == 3 && !reduce {
                ConfettiView(count: 110, duration: 3.6).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: reduce ? 50_000_000 : 950_000_000)
            let stars = session.stars
            if stars < 1 { return }
            for s in 1...stars {
                if Task.isCancelled { return }
                shownStars = s
                ArrowSound.play(.Star, 0)
                Haptics.impactLight()
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
        }
    }
}

private struct ArrowWinStat: View {
    let text: String
    let icon: ImageVector
    let color: Color

    init(_ text: String, _ icon: ImageVector, _ color: Color) {
        self.text = text
        self.icon = icon
        self.color = color
    }

    var body: some View {
        VStack(spacing: 6) {
            Icon(icon, tint: color, size: 19)
            Text(text).font(rounded(11, FontWeight.ExtraBold)).foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

/**
 * The level just solved, replaying on a framed stage: every arrow slides out in the solution
 * order, the cleared cells light up gold so the picture shows, then it plays again.
 */
struct ClearStage: View {
    let level: ArrowLevel
    let animated: Bool

    init(_ level: ArrowLevel, _ animated: Bool) {
        self.level = level
        self.animated = animated
    }

    private final class Data {
        let pieces: [ArrowPiece]
        let rank: [Int]
        let travel: [Double]

        init(_ level: ArrowLevel) {
            let board = ArrowBoard(level)
            let order = board.solutionOrder() ?? Array(board.pieces.indices)
            var rank = [Int](repeating: 0, count: board.pieces.count)
            for (pos, id) in order.enumerated() { rank[id] = pos }
            pieces = board.pieces
            self.rank = rank
            travel = board.pieces.map { Double(board.laneLength($0.id) + $0.cells.count) + 14 }
        }
    }

    @State private var data: Data?
    @State private var start = Date()

    private static let spots: [(CGFloat, CGFloat, CGFloat)] = [(0.07, 0.15, 7), (0.93, 0.12, 6), (0.05, 0.85, 5), (0.95, 0.82, 8), (0.5, 0.05, 5), (0.78, 0.95, 6), (0.22, 0.95, 5)]

    var body: some View {
        let d = data ?? Data(level)
        let shape = RoundedRectangle(cornerRadius: 24, style: .circular)
        TimelineView(.animation(paused: !animated)) { timeline in
            let elapsed = animated ? timeline.date.timeIntervalSince(start) : 0
            Canvas { ctx, size in
                draw(&ctx, size, d, elapsed)
            }
        }
        .background(GeometryReader { g in
            RadialGradient(colors: [hex(0x4A3A9C), hex(0x1B1446)], center: .center, startRadius: 0, endRadius: min(g.size.width, g.size.height) / 2)
        })
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
        .onAppear { if data == nil { data = d } }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ d: Data, _ elapsed: Double) {
        let pieces = d.pieces
        let exitDuration = 0.6
        let settleTime = 0.9
        let step = min(0.12, 2.6 / Double(max(pieces.count, 1)))
        let clearEnd = settleTime + Double(max(pieces.count - 1, 0)) * step + exitDuration
        let period = clearEnd + 1.6 + 0.4
        let t = animated ? elapsed.truncatingRemainder(dividingBy: period) : clearEnd + 1.0
        let loop = animated ? Int(elapsed / period) : 0
        // Rays.
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(size.width, size.height)
        var rays = Path()
        for k in 0..<14 {
            let a = CGFloat(elapsed * 0.12 + Double(k) / 14 * 2 * Double.pi)
            rays.move(to: c)
            rays.addLine(to: CGPoint(x: c.x + cos(a - 0.08) * radius, y: c.y + sin(a - 0.08) * radius))
            rays.addLine(to: CGPoint(x: c.x + cos(a + 0.08) * radius, y: c.y + sin(a + 0.08) * radius))
            rays.closeSubpath()
        }
        ctx.fill(rays, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.1), .clear]), center: c, startRadius: 0, endRadius: radius * 0.7))
        // Board.
        let inset: CGFloat = 18
        let cell = min(30, (size.width - inset * 2) / CGFloat(level.w + 1), (size.height - inset * 2) / CGFloat(level.h + 1))
        let origin = CGPoint(x: (size.width - cell * CGFloat(level.w)) / 2, y: (size.height - cell * CGFloat(level.h)) / 2)
        func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * cell, y: origin.y + p.y * cell) }
        let theme = ArrowTheme.night
        let width = ArrowArt.bodyWidth(cell, theme)
        let reveal = CGFloat(min(max((t - clearEnd + 0.15) / 0.5, 0), 1))
        let pulse = reveal > 0 ? CGFloat(0.75 + 0.25 * sin((t - clearEnd) * 5)) : 0
        let dot = min(max(1.3, cell * 0.2), 3.6) * (1 + 0.35 * reveal)
        // Dots where arrows have left. The glows overlap, so each is its own translucent circle (as on
        // Android); the small dots never touch, so they share one path.
        let glow = hex(0xFFB020, Double(0.35 * reveal * pulse))
        var dots = Path()
        for piece in pieces {
            let leave = settleTime + Double(d.rank[piece.id]) * step
            if t <= leave + exitDuration * 0.25 { continue }
            for cc in piece.cells {
                let p = screen(CGPoint(x: CGFloat(cc.c) + 0.5, y: CGFloat(cc.r) + 0.5))
                if reveal > 0 {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot * 2.2, y: p.y - dot * 2.2, width: dot * 4.4, height: dot * 4.4)), with: .color(glow))
                }
                dots.addEllipse(in: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot))
            }
        }
        ctx.fill(dots, with: .color(reveal > 0 ? hex(0xFFE38A, Double(0.35 + 0.65 * reveal)) : Color.white.opacity(0.22)))
        for piece in pieces {
            let leave = settleTime + Double(d.rank[piece.id]) * step
            var slide = 0.0
            var opacity: CGFloat = 1
            var glow: ArrowRGBA?
            let color = theme.color(piece.id)
            if t < settleTime {
                let p = min(max((t - Double(piece.id % 24) * 0.012) / 0.55, 0), 1)
                let spring = 1 - pow(2.0, -9 * p) * cos(p * 10.5)
                slide = -(1 - spring) * 3
                opacity = loop == 0 && t < 0.05 ? 1 : CGFloat(min(1.0, p * 2.5))
            } else if t >= leave {
                let p = (t - leave) / exitDuration
                if p >= 1 { continue }
                slide = d.travel[piece.id] * pow(p, 1.7)
                opacity = CGFloat(p > 0.75 ? 1 - (p - 0.75) / 0.25 : 1)
                glow = cell >= 6 ? color : nil
            }
            let points = ArrowGeometry.body(piece, slide).map(screen)
            ArrowArt.drawArrow(&ctx, points, ArrowGeometry.direction(points, piece.heading), cell,
                               ArrowArt.Style(color, width, theme.gloss, glow, min(cell * 0.6, 9), opacity))
        }
        // Sparkles.
        for (i, spot) in Self.spots.enumerated() {
            let tw = CGFloat(0.5 + 0.5 * sin(elapsed * 3.1 + Double(i) * 1.7))
            let s = spot.2 * (0.6 + 0.6 * tw)
            let cc = CGPoint(x: size.width * spot.0, y: size.height * spot.1)
            var star = Path()
            star.move(to: CGPoint(x: cc.x, y: cc.y - s))
            star.addQuadCurve(to: CGPoint(x: cc.x + s, y: cc.y), control: cc)
            star.addQuadCurve(to: CGPoint(x: cc.x, y: cc.y + s), control: cc)
            star.addQuadCurve(to: CGPoint(x: cc.x - s, y: cc.y), control: cc)
            star.addQuadCurve(to: CGPoint(x: cc.x, y: cc.y - s), control: cc)
            ctx.fill(star, with: .color((i % 2 == 0 ? Color.white : hex(0xFFE38A)).opacity(Double(0.3 + 0.55 * tw))))
        }
    }
}

// MARK: - Themes

private struct ArrowThemeSheet: View {
    let selection: String
    let dark: Bool
    let onPick: (String) -> Void
    let onDone: () -> Void

    @State private var appear: CGFloat = 0

    var body: some View {
        let lab = Lab.colors
        let choices: [(String, String, ArrowTheme)] = [("auto", "Automatic", ArrowTheme.resolve("auto", dark))] + ArrowTheme.all.map { ($0.id, $0.name, $0) }
        let rows = stride(from: 0, to: choices.count, by: 2).map { Array(choices[$0..<min($0 + 2, choices.count)]) }
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35 * Double(min(max(appear, 0), 1)))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDone() }
            VStack(alignment: .leading, spacing: 16) {
                Capsule().fill(lab.ink2.copy(alpha: 0.4)).frame(width: 40, height: 5).frame(maxWidth: .infinity)
                HStack(spacing: 0) {
                    Text("Board theme").font(LabText.headline).foregroundStyle(lab.ink).frame(maxWidth: .infinity, alignment: .leading)
                    GameButton("Done", colors: GameColors.purple, height: 42, fontSize: 15, onClick: onDone)
                }
                ForEach(0..<rows.count, id: \.self) { r in
                    HStack(spacing: 12) {
                        ForEach(rows[r], id: \.0) { choice in
                            let selected = selection == choice.0
                            VStack(spacing: 6) {
                                ThemePreview(choice.2)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 86)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .circular))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .circular)
                                        .strokeBorder(selected ? lab.brand : lab.glassStroke, lineWidth: selected ? 3 : 1))
                                Text(choice.1).font(rounded(13, FontWeight.ExtraBold)).foregroundStyle(selected ? lab.ink : lab.ink2)
                            }
                            .frame(maxWidth: .infinity)
                            .pressable(0.95) {
                                ArrowSound.play(.Tap)
                                Haptics.tap()
                                onPick(choice.0)
                            }
                        }
                        if rows[r].count == 1 { Spacer().frame(maxWidth: .infinity) }
                    }
                }
            }
            .padding(20)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .circular)
                    .fill(LinearGradient(colors: [lab.bgTop, lab.bgBottom], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea(edges: .bottom)
            )
            .contentShape(Rectangle())
            .onTapGesture {}
            .offset(y: (1 - appear) * 600)
        }
        .onAppear { withAnimation(labSpring(0.5, 0.86)) { appear = 1 } }
    }
}

private let previewPieces: [ArrowPiece] = [
    [(0, 0), (0, 1), (0, 2), (0, 3), (0, 4)], [(2, 1), (1, 1), (1, 2), (1, 3)], [(3, 0), (2, 0), (1, 0)],
    [(2, 2), (2, 3), (2, 4), (1, 4)], [(3, 1), (3, 2), (3, 3), (3, 4), (3, 5)], [(2, 5), (1, 5), (0, 5)],
].enumerated().map { ArrowPiece.of($0.offset, $0.element) }

/// A few arrows on the theme's backdrop.
struct ThemePreview: View {
    let theme: ArrowTheme

    init(_ theme: ArrowTheme) { self.theme = theme }

    var body: some View {
        Canvas { ctx, size in
            let cell = min(size.width / 7.5, size.height / 5)
            let origin = CGPoint(x: (size.width - cell * 6) / 2, y: (size.height - cell * 4) / 2)
            for piece in previewPieces {
                let points = ArrowGeometry.body(piece, 0).map { CGPoint(x: origin.x + $0.x * cell, y: origin.y + $0.y * cell) }
                ArrowArt.drawArrow(&ctx, points, ArrowGeometry.direction(points, piece.heading), cell,
                                   ArrowArt.Style(theme.color(piece.id), ArrowArt.bodyWidth(cell, theme), theme.gloss))
            }
        }
        .background(LinearGradient(colors: [theme.top.color, theme.bottom.color], startPoint: .top, endPoint: .bottom))
    }
}
