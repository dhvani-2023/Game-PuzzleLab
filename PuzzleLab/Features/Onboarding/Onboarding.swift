import SwiftUI

private let PAGE_COUNT = 4

/// First launch: the game wall, brain games, quick fun, then the profile and first-game pick.
struct OnboardingScreen: View {
    let onFinish: (String?) -> Void

    init(onFinish: @escaping (String?) -> Void) { self.onFinish = onFinish }

    @State private var page: Int? = 0
    @State private var startGameID: String?

    private func copy(_ ids: [String], _ line: String) -> String {
        let levels = ids.compactMap { GameRegistry.game($0)?.info.levelCount }.reduce(0, +)
        return "\(line) \(levels.grouped) levels."
    }

    var body: some View {
        let lab = Lab.colors
        let current = page ?? 0
        let isLast = current == PAGE_COUNT - 1
        ZStack {
            LabBackground()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    PinwheelLogo(28)
                    Text("Puzzle Lab").font(LabText.cardTitle).foregroundStyle(lab.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(height: 44)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(0..<PAGE_COUNT, id: \.self) { p in
                            pageView(p, active: current == p)
                                .containerRelativeFrame(.horizontal)
                                .id(p)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .frame(maxHeight: .infinity)
                // Page dots
                HStack(spacing: 7) {
                    ForEach(0..<PAGE_COUNT, id: \.self) { i in
                        Capsule()
                            .fill(i == current ? AnyShapeStyle(lab.brandGradient) : AnyShapeStyle(lab.ink2.copy(alpha: 0.3)))
                            .frame(width: i == current ? 26 : 8, height: 8)
                            .animation(labSpring(0.28, 0.72), value: current)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                LabPrimaryButton(isLast ? "Let's play" : "Next", trailingIcon: isLast ? Icons.Rounded.AutoAwesome : nil) {
                    Haptics.cta()
                    if isLast {
                        UISound.sparkle()
                        onFinish(startGameID)
                    } else {
                        withAnimation(labSpring(0.5, 0.86)) { page = current + 1 }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .onChange(of: page) { _, p in if (p ?? 0) > 0 { UISound.whoosh() } }
    }

    @ViewBuilder
    private func pageView(_ p: Int, active: Bool) -> some View {
        switch p {
        case 0:
            IntroPage(eyebrow: "Welcome to the Lab", title: "Five games.\nOne pocket.",
                      message: "Block puzzles, logic grids, paths, arrow escapes and dots & boxes: \((GameRegistry.totalLevels / 100 * 100).grouped)+ levels, all offline.",
                      offline: true) { GameWall(active: active) }
        case 1:
            IntroPage(eyebrow: "Think it through", title: "Brain games",
                      message: copy(["patches", "zip", "arrowjam"], "Calm logic puzzles, each with exactly one answer.")) {
                GameCardList(ids: ["patches", "zip", "arrowjam"], large: false, active: active)
            }
        case 2:
            IntroPage(eyebrow: "Drop · Clear · Combo", title: "Quick fun",
                      message: copy(["tileburst"], "Drop blocks and clear lines for big, satisfying combos.")) {
                QuickFun(active: active)
            }
        default:
            ProfilePage(startGameID: startGameID) { startGameID = $0 }
        }
    }
}

/// Art on top, then eyebrow, title and copy. Art and text drift at different speeds as the page swipes.
private struct IntroPage<Art: View>: View {
    let eyebrow: String
    let title: String
    let message: String
    var offline: Bool = false
    @ViewBuilder let art: () -> Art

    var body: some View {
        let lab = Lab.colors
        WeightedColumn {
            Color.clear.layoutValue(key: ColumnWeight.self, value: 0.3)
            art()
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                    let a = min(abs(phase.value), 1)
                    return content
                        .offset(x: -phase.value * 90)
                        .scaleEffect(1 - a * 0.12)
                        .opacity(1 - a * 0.6)
                }
            Color.clear.layoutValue(key: ColumnWeight.self, value: 0.2)
            VStack(spacing: 12) {
                if offline {
                    HStack(spacing: 6) {
                        Icon(Icons.Rounded.AirplanemodeActive, tint: lab.ink, size: 14)
                        Text("Works offline · No account").font(rounded(12, .heavy)).foregroundStyle(lab.ink)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .labGlass(15)
                }
                Text(eyebrow.uppercased()).font(LabText.eyebrow).foregroundStyle(lab.brand2)
                Text(title).font(LabText.title).foregroundStyle(lab.ink).multilineTextAlignment(.center)
                Text(message).font(LabText.body).foregroundStyle(lab.ink2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                content
                    .offset(x: -phase.value * 30)
                    .opacity(1 - min(abs(phase.value), 1))
            }
            Color.clear.layoutValue(key: ColumnWeight.self, value: 0.1)
        }
        .clipped()
    }
}

/// Compose `Modifier.weight` for `WeightedColumn` children (0 = sized by its content).
private struct ColumnWeight: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// A column whose weighted children share the height left over by the others (Compose `Column` + `weight`).
private struct WeightedColumn: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let fixed = subviews.filter { $0[ColumnWeight.self] == 0 }
            .reduce(CGFloat(0)) { $0 + $1.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: max(proposal.height ?? fixed, fixed))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var heights = subviews.map { $0[ColumnWeight.self] == 0 ? $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height : 0 }
        let totalWeight = subviews.reduce(CGFloat(0)) { $0 + $1[ColumnWeight.self] }
        let remaining = max(0, bounds.height - heights.reduce(0, +))
        for (i, s) in subviews.enumerated() where s[ColumnWeight.self] > 0 && totalWeight > 0 {
            heights[i] = remaining * s[ColumnWeight.self] / totalWeight
        }
        var y = bounds.minY
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: ProposedViewSize(width: width, height: heights[i]))
            y += heights[i]
        }
    }
}

/// Every game on a tilted wall of glossy tiles. Rows drift slowly in opposite directions behind the
/// Lab's emblem, which glows in the middle.
private struct GameWall: View {
    let active: Bool
    @State private var shown: Double = 0

    var body: some View {
        let lab = Lab.colors
        let reduce = Lab.reduceMotion
        let games = GameRegistry.games
        let tile: CGFloat = 66
        let gap: CGFloat = 14
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [lab.brand.copy(alpha: 0.45), .clear], center: .center, startRadius: 0, endRadius: 190))
                .frame(width: 380, height: 380)
                .opacity(min(max(shown, 0), 1))
            ZStack {
                VStack(spacing: gap) {
                    ForEach(0..<4, id: \.self) { row in
                        WallRow(row: row, games: games, tile: tile, gap: gap, shown: shown, animate: active && !reduce)
                    }
                }
                .rotationEffect(.degrees(-14))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22), .init(color: .black, location: 0.78), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            .clipped()
            PinwheelLogo(84, animateIn: active, startDelayMs: 150)
                .id(active)
                .frame(width: 128, height: 128)
                .background(RoundedRectangle(cornerRadius: 34, style: .circular).fill(lab.bgBottom.copy(alpha: 0.9)))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .circular)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), lab.brand.copy(alpha: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                .labShadow(lab.brand.copy(alpha: 0.7), 30, 0, 34)
                .floating(4)
                .scaleEffect(0.7 + 0.3 * shown)
                .opacity(min(max(shown, 0), 1))
        }
        .onAppear { start() }
        .onChange(of: active) { _, _ in start() }
    }

    private func start() {
        guard active else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { shown = 0 }
        DispatchQueue.main.async { withAnimation(labSpring(0.6, 0.88)) { shown = 1 } }
    }
}

/// One drifting row of the wall: four copies of every game's badge, sliding one span per cycle.
private struct WallRow: View {
    let row: Int
    let games: [any GameModule]
    let tile: CGFloat
    let gap: CGFloat
    let shown: Double
    let animate: Bool
    @State private var drift = false

    var body: some View {
        let order = games.indices.map { games[($0 + row * 3) % games.count] }
        let span = CGFloat(order.count) * (tile + gap)
        let speed: CGFloat = 8 + CGFloat(row % 2) * 3
        let even = row % 2 == 0
        let travel = drift ? span / 2 : -span / 2
        let base = CGFloat(row) * (tile + gap) * 0.5
        let x = (even ? travel : -travel) + base
        let rowIn = min(max(shown * 4 - Double(row) * 0.28, 0), 1)
        HStack(spacing: gap) {
            ForEach(0..<4, id: \.self) { copy in
                ForEach(Array(order.enumerated()), id: \.offset) { _, m in
                    GameBadgeFrame(m.info.colors, tile, glow: false) { m.BadgeArt(53) }
                        .labShadow(Color.black.opacity(0.25), 6, 4, 15)
                }
            }
        }
        .fixedSize()
        .offset(x: x)
        .offset(x: (1 - rowIn) * (even ? -40 : 40))
        .frame(width: 900, alignment: .leading)
        .opacity(rowIn)
        .onAppear { startDrift(span: span, speed: speed) }
        .onChange(of: animate) { _, _ in startDrift(span: span, speed: speed) }
    }

    private func startDrift(span: CGFloat, speed: CGFloat) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { drift = false }
        guard animate else { return }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: Double(span / speed)).repeatForever(autoreverses: false)) { drift = true }
        }
    }
}

/// Games as cards: badge, name, hook and facts, sliding in one after another.
private struct GameCardList: View {
    let ids: [String]
    let large: Bool
    let active: Bool

    var body: some View {
        let modules = ids.compactMap { GameRegistry.game($0) }
        VStack(spacing: large ? 16 : 12) {
            ForEach(Array(modules.enumerated()), id: \.offset) { index, module in
                ListedCard(module: module, large: large, index: index, active: active, floats: index == modules.count / 2)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ListedCard: View {
    let module: any GameModule
    let large: Bool
    let index: Int
    let active: Bool
    let floats: Bool
    @State private var shown = false

    var body: some View {
        GameCard(module: module, large: large)
            .floating(3, active: floats && active)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear { if active { show() } }
            .onChange(of: active) { _, a in if a { show() } }
    }

    private func show() {
        withAnimation(labSpring(0.6, 0.88).delay(Double(index) * 0.06)) { shown = true }
    }
}

private struct GameCard: View {
    let module: any GameModule
    let large: Bool

    var body: some View {
        let lab = Lab.colors
        let pitch = pitchOf(module.info.id)
        HStack(spacing: 12) {
            GameBadgeFrame(module.info.colors, large ? 78 : 58, glow: false) { module.BadgeArt(large ? 62 : 46) }
            VStack(alignment: .leading, spacing: 3) {
                Text(module.info.name).font(rounded(large ? 21 : 17, .heavy)).foregroundStyle(lab.ink)
                Text(pitch.hook).font(rounded(large ? 14 : 13, .semibold)).foregroundStyle(lab.ink2).lineLimit(2)
                HStack(spacing: 4) {
                    Icon(Icons.Rounded.Timer, tint: module.info.first, size: 12)
                    Text("\(pitch.minutes) min · \(module.info.levelCount.grouped) levels").font(rounded(11, .heavy)).foregroundStyle(module.info.first)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(large ? 16 : 12)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity)
        .labGlass(22)
        .overlay(alignment: .leading) {
            Capsule().fill(module.info.gradient).frame(width: 4, height: large ? 76 : 56).padding(.leading, 7)
        }
    }
}

/// Tile Burst's page: its live board above its card.
private struct QuickFun: View {
    let active: Bool
    @State private var shown: Double = 0

    var body: some View {
        if let module = GameRegistry.game("tileburst") {
            VStack(spacing: 14) {
                Group {
                    if active { module.Artwork() } else { module.BadgeArt(146) }
                }
                .padding(12)
                .frame(width: 170, height: 170)
                .background(RoundedRectangle(cornerRadius: 30, style: .circular).fill(module.info.gradient))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .circular))
                .labShadow(module.info.first.copy(alpha: 0.5), 20, 10, 30)
                .scaleEffect(0.85 + 0.15 * shown)
                .opacity(min(max(shown, 0), 1))
                GameCard(module: module, large: true)
                    .opacity(min(max(shown, 0), 1))
                    .offset(y: (1 - shown) * 16)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { if active { withAnimation(labSpring(0.42, 0.6)) { shown = 1 } } }
            .onChange(of: active) { _, a in if a { withAnimation(labSpring(0.42, 0.6)) { shown = 1 } } }
        }
    }
}

/// "Who's playing?": an avatar, an optional name, feedback toggles and a first game.
private struct ProfilePage: View {
    let startGameID: String?
    let onPick: (String?) -> Void

    @Environment(AppState.self) private var app
    @FocusState private var nameFocused: Bool

    var body: some View {
        let lab = Lab.colors
        let profile = app.profile
        let settings = app.settings
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("MAKE IT YOURS").font(LabText.eyebrow).foregroundStyle(lab.brand2)
                    Text("Who's playing?").font(LabText.title).foregroundStyle(lab.ink)
                }
                .padding(.top, 20)
                AvatarPicker(profile: profile)
                ZStack {
                    if profile.name.isEmpty {
                        Text("Your name (optional)").font(rounded(17, .bold)).foregroundStyle(lab.ink2.copy(alpha: 0.7)).allowsHitTesting(false)
                    }
                    TextField("", text: Binding(get: { profile.name }, set: { profile.updateName($0) }))
                        .font(rounded(17, .bold))
                        .foregroundStyle(lab.ink)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit { nameFocused = false }
                        .tint(lab.brand)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .labGlass(Lab.Radius.small)
                .padding(.horizontal, 24)
                VStack(spacing: 0) {
                    SettingsRow(Icons.Rounded.VolumeUp, hex(0xFF5C93), "Sound effects") {
                        LabToggle(settings.soundEnabled) { settings.updateSound($0) }
                    }
                    GlassDivider()
                    SettingsRow(Icons.Rounded.Vibration, hex(0x2FB9A0), "Haptics") {
                        LabToggle(settings.hapticsEnabled) { settings.updateHaptics($0) }
                    }
                }
                .labGlass()
                .padding(.horizontal, 24)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start with…").font(LabText.label).foregroundStyle(lab.ink2).padding(.horizontal, 24)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(GameRegistry.games, id: \.info.id) { module in
                                let selected = startGameID == module.info.id
                                VStack(spacing: 6) {
                                    GameBadgeFrame(module.info.colors, 56, glow: selected) { module.BadgeArt(45) }
                                        .overlay(alignment: .topTrailing) {
                                            if selected {
                                                Icon(Icons.Rounded.CheckCircle, tint: lab.ok, size: 22)
                                                    .background(Circle().fill(Color.white).padding(2))
                                                    .offset(x: 6, y: -6)
                                            }
                                        }
                                        .scaleEffect(selected ? 1.08 : 1)
                                        .animation(labSpring(0.28, 0.72), value: selected)
                                    Text(module.info.name).font(rounded(11, .heavy)).foregroundStyle(selected ? lab.ink : lab.ink2)
                                }
                                .pressable(0.92) {
                                    UISound.tap()
                                    Haptics.tap()
                                    onPick(selected ? nil : module.info.id)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
