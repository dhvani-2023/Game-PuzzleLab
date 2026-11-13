import SwiftUI

/// The short sell for a game on the showcase.
struct GamePitch {
    let hook: String
    let minutes: Int
}

func pitchOf(_ id: String) -> GamePitch {
    switch id {
    case "tileburst": return GamePitch(hook: "Drop blocks, clear lines, chain combos", minutes: 3)
    case "arrowjam": return GamePitch(hook: "Free every arrow and reveal the picture", minutes: 1)
    case "patches": return GamePitch(hook: "Cut the grid into perfect rectangles", minutes: 3)
    case "zip": return GamePitch(hook: "One line through every cell, in order", minutes: 1)
    default: return GamePitch(hook: "A fresh puzzle to crack", minutes: 2)
    }
}

func greeting() -> String {
    switch Days.hourOfDay() {
    case 5...11: return "Good morning"
    case 12...16: return "Good afternoon"
    case 17...21: return "Good evening"
    default: return "Night owl mode"
    }
}

/// A player's colour from their profile.
func profileColor(_ index: Int) -> Color {
    let n = PlayerProfile.TOKEN_PATCHES.count
    return Lab.colors.patch(PlayerProfile.TOKEN_PATCHES[((index % n) + n) % n])
}

/// The player's avatar inside a ring that fills toward the next Lab level.
struct LabLevelAvatar: View {
    var size: CGFloat = 52

    init(_ size: CGFloat = 52) { self.size = size }

    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let xp = app.store.labXP
        ZStack {
            ProgressRing(Double(LabLevel.progress(xp)), max(3, size * 0.08), lab.glass,
                         LinearGradient(colors: [lab.sun, hex(0xFF8A3D)], startPoint: .top, endPoint: .bottom))
            ProfileAvatar(app.profile.avatar, profileColor(app.profile.colorIndex), size * 0.76)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            Text("\(LabLevel.level(xp))")
                .font(rounded(max(10, size * 0.22), .black))
                .foregroundStyle(hex(0x3A2400))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: size * 0.36, height: size * 0.36)
                .background(Circle().fill(lab.sun))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
                .offset(x: 4, y: 3)
        }
    }
}

/// Fades and lifts an item in when a tab first appears, staggered by `index`.
struct Appear<Content: View>: View {
    let index: Int
    @ViewBuilder let content: () -> Content

    init(_ index: Int, @ViewBuilder content: @escaping () -> Content) {
        self.index = index
        self.content = content
    }

    @State private var shown = false

    var body: some View {
        let t: Double = shown ? 1 : 0
        content()
            .opacity(t)
            .offset(y: (1 - t) * 18)
            .scaleEffect(0.98 + 0.02 * t)
            .onAppear {
                if Lab.reduceMotion {
                    shown = true
                } else {
                    withAnimation(labSpring(0.6, 0.88).delay(Double(Motion.stagger(index)) / 1000)) { shown = true }
                }
            }
    }
}

struct HomeTab: View {
    let bottomInset: CGFloat

    init(_ bottomInset: CGFloat) { self.bottomInset = bottomInset }

    @Environment(AppState.self) private var app
    @State private var driver = ScrollDriver()
    @State private var scrolled = false
    @State private var focus: String?
    @State private var headerHeight: CGFloat = 80
    @State private var since: Int64 = HomeTab.spotlightSince()

    private static func spotlightSince() -> Int64 {
        let key = "home.spotlightSince.\(GameRegistry.SPOTLIGHT_ID)"
        if let stored = Prefs.string(key), let v = Int64(stored) { return v }
        let now = Days.nowMillis()
        Prefs.putString(key, String(now))
        return now
    }

    var body: some View {
        let store = app.store
        let router = app.router
        let spotlightIsNew = Days.nowMillis() - since < 7 * 86_400_000
        let states = GameRegistry.games.map { m -> HomePlanner.GameState in
            let p = store.progress(m.info.id)
            return HomePlanner.GameState(m.info.id, p.solvedCount, p.isComplete)
        }
        let spotlight = spotlightIsNew ? GameRegistry.SPOTLIGHT_ID : nil
        let pickID = HomePlanner.todaysPick(states, Days.dayNumber(), spotlight)
        let pickIsNew = pickID != nil && pickID == spotlight
        let continueIDs = HomePlanner.continueGames(states, pickID, store.lastPlayedGameID)
        ZStack(alignment: .top) {
            DrivenScrollView(driver: driver, onOffset: { y in
                let s = y > 80
                if s != scrolled { scrolled = s }
            }) {
                VStack(spacing: 24) {
                    Appear(0) { HomeHeader { router.tab = .Settings } }
                        .background(GeometryReader { g in Color.clear.onAppear { headerHeight = g.size.height } })
                    Appear(1) {
                        VStack(spacing: 16) {
                            GameShowcase(pickID: pickID, pickIsNew: pickIsNew, focus: focus, onFocusHandled: { focus = nil }) { router.play($0, store) }
                            LabTourRibbon {
                                let played = Set(store.tourGames)
                                focus = showcaseOrder(store, pickID).first { !played.contains($0.info.id) }?.info.id
                                driver.scrollTo(y: headerHeight + 8 + 24, animated: true)
                            }
                        }
                    }
                    if !continueIDs.isEmpty {
                        Appear(3) { ContinueSection(ids: continueIDs) { router.tab = .Games } }
                    }
                    Appear(4) { DailySection() }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, bottomInset + 24)
            }
            if scrolled {
                CompactHomeHeader { router.tab = .Settings }
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity).animation(labSpring(0.28, 0.72)),
                                            removal: .move(edge: .top).combined(with: .opacity).animation(tween(200))))
                    .zIndex(1)
            }
        }
        .animation(labSpring(0.28, 0.72), value: scrolled)
    }
}

private struct HomeHeader: View {
    let onSettings: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        HStack(spacing: 10) {
            LabLevelAvatar(48)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting()).font(gameTextStyle(20)).foregroundStyle(lab.ink).lineLimit(1).truncationMode(.tail)
                Text("\(app.profile.displayName) · Lab level \(LabLevel.level(app.store.labXP))").font(LabText.caption).foregroundStyle(lab.ink2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatPill(Icons.Rounded.LocalFireDepartment, "\(app.store.streak)", lab.warn)
            GlassIconButton(Icons.Rounded.Settings, onClick: onSettings)
        }
        .padding(.top, 8)
    }
}

private struct CompactHomeHeader: View {
    let onSettings: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LabLevelAvatar(36)
                Text("Puzzle Lab").font(LabText.cardTitle).foregroundStyle(lab.ink).frame(maxWidth: .infinity, alignment: .leading)
                StatPill(Icons.Rounded.LocalFireDepartment, "\(app.store.streak)", lab.warn)
                GlassIconButton(Icons.Rounded.Settings, size: 36, onClick: onSettings)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(lab.bgTop.ignoresSafeArea(edges: .top))
            Rectangle().fill(lab.glassStroke).frame(height: 1)
        }
    }
}

/// Today's pick first, then games not tried yet, then in progress, then completed.
func showcaseOrder(_ store: ProgressStore, _ pickID: String?) -> [any GameModule] {
    func rank(_ m: any GameModule) -> Int {
        let p = store.progress(m.info.id)
        if m.info.id == pickID { return 0 }
        if p.solvedCount == 0 { return 1 }
        if p.isComplete { return 3 }
        return 2
    }
    return GameRegistry.games.enumerated()
        .sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }
        .map { $0.element }
}

/// Home's top: every game on a big swipeable poster card with its live artwork. The cards move on by
/// themselves every 6 s until the player swipes.
private struct GameShowcase: View {
    let pickID: String?
    let pickIsNew: Bool
    let focus: String?
    let onFocusHandled: () -> Void
    let onPlay: (any GameModule) -> Void

    @Environment(AppState.self) private var app
    @State private var currentID: String?
    /// The page we moved to ourselves; any other page change came from the player's swipe.
    @State private var expectedID: String?
    @State private var swiped = false
    @State private var fill: CGFloat = 0
    @State private var cardWidth: CGFloat = 335

    var body: some View {
        let lab = Lab.colors
        let reduce = Lab.reduceMotion
        let entries = showcaseOrder(app.store, pickID)
        let ids = entries.map { $0.info.id }
        let currentIndex = currentID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let current = entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
        let glowA = current?.info.first ?? lab.brand
        let glowB = current?.info.last ?? lab.brand2
        VStack(spacing: 12) {
            ZStack {
                if !reduce {
                    // The top of home takes on the current game's colours: a soft, unclipped glow.
                    RoundedRectangle(cornerRadius: 60, style: .circular)
                        .fill(LinearGradient(colors: [glowA.copy(alpha: 0.32), glowB.copy(alpha: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .padding(.horizontal, 30)
                        .padding(.top, 34)
                        .padding(.bottom, 6)
                        .blur(radius: 27)
                        .animation(tween(500), value: currentIndex)
                        .allowsHitTesting(false)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40) {
                        ForEach(Array(entries.enumerated()), id: \.element.info.id) { page, module in
                            let active = page == currentIndex
                            ShowcaseCard(module: module, badge: badgeFor(module, pickID, pickIsNew), active: active) {
                                swiped = true
                                Haptics.cta()
                                onPlay(module)
                            }
                            .frame(width: cardWidth)
                            .padding(.top, 6)
                            .padding(.bottom, 26)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                let a = min(abs(phase.value), 1)
                                return content
                                    .scaleEffect(reduce ? 1 : 1 - a * 0.08)
                                    .opacity(1 - a * 0.3)
                            }
                            .id(module.info.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $currentID)
                // Wider than the column by the gutters, so each card's shadow has room.
                .padding(.horizontal, -20)
            }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { cardWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in cardWidth = w }
            })
            // A pill per game in its colours; the current one stretches and fills as the timer runs.
            HStack(spacing: 6) {
                ForEach(Array(entries.enumerated()), id: \.element.info.id) { i, m in
                    let isCurrent = i == currentIndex
                    ZStack(alignment: .leading) {
                        Capsule().fill(lab.ink2.copy(alpha: 0.22))
                        if isCurrent {
                            Rectangle().fill(LinearGradient(colors: m.info.colors, startPoint: .leading, endPoint: .trailing))
                                .frame(width: 28 * fill)
                        } else {
                            Rectangle().fill(m.info.first.copy(alpha: 0.7))
                        }
                    }
                    .frame(width: isCurrent ? 28 : 8, height: 8)
                    .clipShape(Capsule())
                    .animation(labSpring(0.28, 0.72), value: isCurrent)
                }
            }
            .frame(maxWidth: .infinity)
            .offset(y: -18)
        }
        .onAppear {
            if currentID == nil {
                expectedID = ids.first
                currentID = ids.first
            }
        }
        .onChange(of: focus) { _, id in
            guard let id else { return }
            swiped = true
            if ids.contains(id) {
                expectedID = id
                withAnimation(labSpring(0.5, 0.86)) { currentID = id }
            }
            onFocusHandled()
        }
        .onChange(of: currentID) { _, new in
            if new != expectedID && !swiped { swiped = true }
            expectedID = nil
            let index = new.flatMap { ids.firstIndex(of: $0) } ?? 0
            if index > 0 || swiped { UISound.whoosh() }
        }
        .task(id: "\(currentIndex)-\(swiped)-\(reduce)-\(ids.count)") {
            if swiped || reduce {
                fill = 1
                return
            }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { fill = 0 }
            try? await Task.sleep(nanoseconds: 30_000_000)
            withAnimation(.linear(duration: 6)) { fill = 1 }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if Task.isCancelled || ids.isEmpty { return }
            let next = ids[(currentIndex + 1) % ids.count]
            expectedID = next
            withAnimation(labSpring(0.5, 0.86)) { currentID = next }
        }
    }
}

private func badgeFor(_ module: any GameModule, _ pickID: String?, _ pickIsNew: Bool) -> (String, ImageVector) {
    if module.info.id == pickID {
        return pickIsNew ? ("New game", Icons.Rounded.AutoAwesome) : ("Today's pick", Icons.Rounded.Event)
    }
    return ("Keep going", Icons.Rounded.LocalFireDepartment)
}

private struct ShowcaseCard: View {
    let module: any GameModule
    let badge: (String, ImageVector)
    let active: Bool
    let onPlay: () -> Void

    @Environment(AppState.self) private var app
    @State private var shimmer: CGFloat = 0
    @State private var shimmering = false

    var body: some View {
        let reduce = Lab.reduceMotion
        let info = module.info
        let progress = app.store.progress(info.id)
        let realBadge: (String, ImageVector) = {
            if badge.0 != "Keep going" { return badge }
            if progress.isComplete { return ("Completed", Icons.Rounded.Verified) }
            if progress.solvedCount == 0 { return ("Not tried yet", Icons.Rounded.AutoAwesome) }
            return badge
        }()
        let shape = RoundedRectangle(cornerRadius: Lab.Radius.hero, style: .circular)
        let glow: Double = active ? 0.45 : 0.12
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [info.first.mix(.white, 0.08), info.last.mix(.black, 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ShowcaseAmbience(animating: active && !reduce)
            GeometryReader { g in
                let c = CGPoint(x: g.size.width * 0.5, y: g.size.height * 0.38)
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0)], center: .center, startRadius: 0, endRadius: 140))
                    .frame(width: 280, height: 280)
                    .position(c)
            }
            ShowcaseArt(module: module, active: active)
                .scaleEffect(0.9)
                .floating(5, active: active)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -34)
            LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: Color.black.opacity(0.32), location: 1)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Icon(realBadge.1, tint: .white, size: 13)
                    Text(realBadge.0.uppercased()).font(rounded(11, .heavy)).tracking(1.1).foregroundStyle(Color.white).lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.black.opacity(0.18)))
                .overlay {
                    if shimmering {
                        GeometryReader { g in
                            LinearGradient(colors: [.clear, Color.white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 40)
                                .offset(x: -60 + (g.size.width + 100) * shimmer)
                        }
                        .clipShape(Capsule())
                        .allowsHitTesting(false)
                    }
                }
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.name).font(rounded(28, .black)).foregroundStyle(Color.white).lineLimit(1)
                            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                        Text(pitchOf(info.id).hook).font(rounded(13, .bold)).foregroundStyle(Color.white.opacity(0.92)).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack(alignment: .top) {
                        PlayPulse(active: active && !reduce)
                            .frame(width: 62, height: 62)
                        GameIconButton(Icons.Rounded.PlayArrow, colors: GameColors.white, size: 62, iconSize: 36, iconTint: info.last.mix(.black, 0.15), onClick: onPlay)
                    }
                    .frame(width: 64, height: 68, alignment: .top)
                }
            }
            .padding(16)
            if progress.solvedCount > 0 {
                let fraction = CGFloat(progress.solvedCount) / CGFloat(max(progress.levelCount, 1))
                VStack {
                    Spacer()
                    GeometryReader { g in
                        Rectangle().fill(Color.white.opacity(0.9)).frame(width: max(10, g.size.width * fraction), height: 4)
                    }
                    .frame(height: 4)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        .labShadow(info.first.mix(.black, 0.25).copy(alpha: glow * 0.85), 20, 10, Lab.Radius.hero)
        .animation(tween(300), value: active)
        .pressable(0.97, onClick: onPlay)
        .task(id: active) {
            guard active, !reduce else { return }
            shimmer = 0
            shimmering = true
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(tween(900)) { shimmer = 1 }
            try? await Task.sleep(nanoseconds: 950_000_000)
            shimmering = false
        }
    }
}

/// The ring that pulses out of the active card's play key (1.6 s loop).
private struct PlayPulse: View {
    let active: Bool

    var body: some View {
        if active {
            TimelineView(.animation) { tl in
                let pulse = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                Canvas { ctx, s in
                    _ = pulse
                    let r = min(s.width, s.height) / 2 * (1 + 0.35 * pulse)
                    let c = CGPoint(x: s.width / 2, y: s.height / 2)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(Color.white.opacity(0.9 * (1 - pulse))), lineWidth: 2)
                }
                .padding(-14)
            }
            .allowsHitTesting(false)
        }
    }
}

/// A game's live artwork on its own framed panel, tilted back a little: Patches and Zip sit on frosted
/// glass, Tile Burst and Arrow Jam bring their own backdrops.
struct ShowcaseArt: View {
    let module: any GameModule
    let active: Bool

    init(module: any GameModule, active: Bool) {
        self.module = module
        self.active = active
    }

    var body: some View {
        let id = module.info.id
        let size: CGSize = id == "tileburst" ? CGSize(width: 176, height: 150) : (id == "arrowjam" ? CGSize(width: 150, height: 150) : CGSize(width: 200, height: 200))
        let glass = id == "patches" || id == "zip"
        let shape = RoundedRectangle(cornerRadius: 26, style: .circular)
        Group {
            if active {
                module.Artwork()
            } else {
                module.BadgeArt(min(size.width, size.height) * 0.7)
            }
        }
        .padding(glass ? 12 : 0)
        .frame(width: size.width, height: size.height)
        .background {
            if glass {
                ZStack {
                    Color.white.opacity(0.12)
                    LinearGradient(stops: [.init(color: Color.white.opacity(0.14), location: 0), .init(color: .clear, location: 0.5)], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(glass ? 0.22 : 0.45), lineWidth: 1.2))
        .labShadow(Color.black.opacity(0.28), 16, 10, 26)
        .rotation3DEffect(.degrees(8), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
    }
}

/// Light rays turning slowly round the art, and sparkles drifting up.
private struct ShowcaseAmbience: View {
    let animating: Bool
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: !animating)) { tl in
            let t = animating ? tl.date.timeIntervalSince(start) : 0
            Canvas { ctx, size in
                let c = CGPoint(x: size.width * 0.5, y: size.height * 0.38)
                let reach = max(size.width, size.height)
                let turn = t * 0.12
                let shading = GraphicsContext.Shading.radialGradient(Gradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)]), center: c, startRadius: 0, endRadius: reach * 0.7)
                for i in 0..<14 {
                    let a = Double(i) / 14 * 2 * .pi + turn
                    var path = Path()
                    path.move(to: c)
                    path.addLine(to: CGPoint(x: c.x + cos(a - 0.09) * reach, y: c.y + sin(a - 0.09) * reach))
                    path.addLine(to: CGPoint(x: c.x + cos(a + 0.09) * reach, y: c.y + sin(a + 0.09) * reach))
                    path.closeSubpath()
                    ctx.fill(path, with: shading)
                }
                for k in 0..<16 {
                    let seed = Double(k) * 12.9898
                    let fx = (sin(seed) * 43_758.5453).truncatingRemainder(dividingBy: 1.0)
                    let x = abs(fx) * size.width
                    let speed = Double(10 + (k % 5) * 4)
                    let cycle = size.height + 40
                    let y = size.height + 20 - (t * speed + Double(k) * 61).truncatingRemainder(dividingBy: cycle)
                    let sway = sin(t * 0.8 + Double(k)) * 8
                    let r = 1.5 + Double(k % 4) * 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: x + sway - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(Color.white.opacity(0.18 + Double(k % 3) * 0.1)))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: animating) { _, on in if on { start = Date() } }
    }
}

/// "Play 3 different games today": three slots that fill with each new game's badge.
private struct LabTourRibbon: View {
    let onFind: () -> Void
    @Environment(AppState.self) private var app
    @State private var celebrating = false

    var body: some View {
        let lab = Lab.colors
        let played = app.store.tourGames
        let done = played.count >= LabTour.GOAL
        let shape = RoundedRectangle(cornerRadius: Lab.Radius.card, style: .circular)
        HStack(spacing: 12) {
            Icon(done ? Icons.Rounded.Verified : Icons.Rounded.Explore, tint: done ? hex(0x3A2400) : lab.brand, size: 22)
                .frame(width: 36, height: 36)
                .background(Circle().fill(done ? Color.white.opacity(0.6) : lab.brand.copy(alpha: 0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Lab Tour").font(rounded(15, .heavy)).foregroundStyle(done ? hex(0x3A2400) : lab.ink)
                Text(done ? "Tour complete · come back tomorrow" : "Play \(LabTour.GOAL) different games today · +\(LabTour.XP) XP")
                    .font(rounded(12, .bold)).foregroundStyle(done ? hex(0x5A3A00) : lab.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(0..<LabTour.GOAL, id: \.self) { slot in
                    if slot < played.count, let module = GameRegistry.game(played[slot]) {
                        TourSlotBadge(module: module).id(played[slot])
                    } else {
                        Text("?").font(rounded(15, .black)).foregroundStyle(lab.ink2)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().inset(by: 1).stroke(lab.ink2.copy(alpha: 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                            .pressable(0.9, sound: true, onClick: onFind)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .labGlass(Lab.Radius.card)
        .background {
            if done { LinearGradient(colors: [hex(0xFFE27A), hex(0xF0A21C)], startPoint: .topLeading, endPoint: .bottomTrailing) }
        }
        .overlay {
            if celebrating { ConfettiView(count: 40, duration: 1.5) }
        }
        .clipShape(shape)
        .task(id: done) {
            let today = String(Days.dayNumber())
            guard done, Prefs.string("home.labTour.celebrated") != today else { return }
            Prefs.putString("home.labTour.celebrated", today)
            UISound.sparkle()
            Haptics.success()
            celebrating = true
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            celebrating = false
        }
    }
}

private struct TourSlotBadge: View {
    let module: any GameModule
    @State private var scale: CGFloat = 0.3

    var body: some View {
        GameBadgeFrame(module.info.colors, 34, glow: false) { module.BadgeArt(27) }
            .scaleEffect(scale)
            .onAppear { withAnimation(labSpring(0.42, 0.6)) { scale = 1 } }
    }
}

private struct ContinueSection: View {
    let ids: [String]
    let onSeeAll: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 12) {
            SectionHeader("Continue", action: "See all", onAction: onSeeAll)
            VStack(spacing: 8) {
                ForEach(ids.compactMap { GameRegistry.game($0) }, id: \.info.id) { module in
                    let progress = app.store.progress(module.info.id)
                    HStack(spacing: 12) {
                        GameBadgeFrame(module.info.colors, 50, glow: false) { module.BadgeArt(40) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.info.name).font(LabText.cardTitle).foregroundStyle(lab.ink)
                            Text("Level \(progress.currentLevel) · \(progress.solvedCount.grouped) of \(progress.levelCount.grouped) solved")
                                .font(LabText.caption).foregroundStyle(lab.ink2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        GameIconButton(Icons.Rounded.PlayArrow, colors: module.info.colors, size: 42, iconSize: 24) { app.router.play(module, app.store) }
                    }
                    .padding(12)
                    .labGlass(Lab.Radius.card)
                    .pressable(0.97) { app.router.play(module, app.store) }
                }
            }
        }
    }
}

private struct DailySection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let modules = GameRegistry.games.filter { $0.daily != nil }
        if !modules.isEmpty {
            VStack(spacing: 12) {
                SectionHeader("Daily")
                ForEach(modules, id: \.info.id) { module in
                    if let daily = module.daily {
                        HStack(spacing: 12) {
                            GameBadgeFrame(module.info.colors, 54, glow: false) { module.BadgeArt(43) }
                                .overlay(alignment: .bottomTrailing) {
                                    Icon(Icons.Rounded.CalendarMonth, tint: .white, size: 13)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(lab.warn))
                                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                                        .offset(x: 6, y: 6)
                                }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(daily.title).font(LabText.cardTitle).foregroundStyle(lab.ink)
                                Text(daily.detail).font(LabText.caption).foregroundStyle(lab.ink2).lineLimit(2)
                                if daily.streak > 0 {
                                    HStack(spacing: 3) {
                                        Icon(Icons.Rounded.LocalFireDepartment, tint: lab.warn, size: 12)
                                        Text("\(daily.streak)-day streak").font(rounded(11, .heavy)).foregroundStyle(lab.warn)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if daily.isDone {
                                Icon(Icons.Rounded.CheckCircle, tint: lab.ok, size: 32)
                            } else {
                                GameButton("Play", colors: module.info.colors, height: 42, fontSize: 15) {
                                    UISound.whoosh()
                                    app.router.push(.Daily(module.info.id))
                                }
                            }
                        }
                        .padding(12)
                        .labGlass(Lab.Radius.card)
                        .pressable(0.97) {
                            UISound.whoosh()
                            app.router.push(.Daily(module.info.id))
                        }
                    }
                }
            }
        }
    }
}
