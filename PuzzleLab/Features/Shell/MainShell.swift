import SwiftUI

/// The tab shell, with game, map and settings screens pushed full-screen over it.
struct MainShell: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let router = app.router
        let top = router.top
        GeometryReader { geo in
            ZStack {
                routeView(top)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .id(top?.key ?? "shell")
                    .transition(RouteTransition(width: geo.size.width, router: router))
            }
            .animation(labSpring(0.5, 0.86), value: top?.key ?? "shell")
        }
    }

    @ViewBuilder
    private func routeView(_ route: Route?) -> some View {
        switch route {
        case nil:
            ShellTabs()
        case .Levels(let id):
            if let m = GameRegistry.game(id) { JourneyMapScreen(m) }
        case .Play(let id, let level):
            if let m = GameRegistry.game(id) { m.PlayScreen(level) }
        case .Daily(let id):
            if let m = GameRegistry.game(id) { m.DailyScreen() }
        case .Settings:
            ZStack {
                LabBackground()
                SettingsScreen(24, embedded: false)
            }
        case .Legal(let doc):
            LegalScreen(LegalDoc.of(doc))
        }
    }
}

/// Push: the new screen slides in a third of the way and grows from 96% while the old one shrinks and
/// fades. Pop: the reverse. The direction is read when each transition starts.
private struct RouteTransition: Transition {
    let width: CGFloat
    let router: Router

    func body(content: Content, phase: TransitionPhase) -> some View {
        let forward = router.lastForward
        var dx: CGFloat = 0, scale: CGFloat = 1, alpha: Double = 1
        switch phase {
        case .willAppear:
            if forward { dx = width / 3; scale = 0.96 } else { scale = 0.94 }
            alpha = 0
        case .didDisappear:
            if forward { scale = 0.94 } else { dx = width / 3 }
            alpha = 0
        case .identity:
            break
        }
        return content
            .offset(x: dx)
            .scaleEffect(scale)
            .opacity(alpha)
    }
}

private struct ShellTabs: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geo in
            let safeBottom = geo.safeAreaInsets.bottom
            // Android hides its navigation bar and floats the dock 8 dp off the edge; on iPhone the dock
            // sits just above the home indicator.
            let dockBottom = safeBottom > 0 ? max(8, safeBottom - 12) : 8
            let bottomInset = 68 + 14 + (dockBottom - 8)
            ZStack(alignment: .bottom) {
                LabBackground()
                ZStack {
                    tab(app.router.tab, bottomInset)
                        .id(app.router.tab)
                        .transition(.opacity)
                }
                .animation(tween(220), value: app.router.tab)
                .ignoresSafeArea(edges: .bottom)
                LabTabBar()
                    .padding(.bottom, dockBottom)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    @ViewBuilder
    private func tab(_ tab: AppTab, _ inset: CGFloat) -> some View {
        switch tab {
        case .Home: HomeTab(inset)
        case .Games: GamesTab(inset)
        case .Progress: ProgressTab(inset)
        case .Settings: SettingsScreen(inset)
        }
    }
}

/// A floating game tray. The selected tab sits on a 3D key that slides between tabs, and its icon gives
/// a small bounce.
private struct LabTabBar: View {
    @Environment(AppState.self) private var app
    @State private var bounces: [CGFloat] = Array(repeating: 1, count: AppTab.allCases.count)

    var body: some View {
        let lab = Lab.colors
        let router = app.router
        let tabs = AppTab.allCases
        let selected = tabs.firstIndex(of: router.tab) ?? 0
        let tray = lab.isDark ? [hex(0x352D74), hex(0x1C1744)] : [Color.white, hex(0xEDE9F8)]
        let shape = RoundedRectangle(cornerRadius: 28, style: .circular)
        GeometryReader { g in
            let itemWidth = (g.size.width - 4 * CGFloat(tabs.count - 1)) / CGFloat(tabs.count)
            ZStack(alignment: .topLeading) {
                TabKey()
                    .frame(width: itemWidth, height: g.size.height)
                    .offset(x: CGFloat(selected) * (itemWidth + 4))
                    .animation(labSpring(0.3, 0.7), value: selected)
                HStack(spacing: 4) {
                    ForEach(Array(tabs.enumerated()), id: \.element) { i, tab in
                        let isSelected = i == selected
                        let color = isSelected ? Color.white : lab.ink2
                        VStack(spacing: 2) {
                            Icon(tab.icon, tint: color, size: 24)
                                .scaleEffect(bounces[i] * (isSelected ? 1.1 : 1))
                                .offset(y: isSelected ? -2 : 0)
                                .animation(labSpring(0.35, 0.55), value: isSelected)
                            if isSelected {
                                Text(tab.title).font(gameTextStyle(10.5, GameColors.purple[1].mix(.black, 0.45).copy(alpha: 0.7))).foregroundStyle(color).lineLimit(1)
                            } else {
                                Text(tab.title).font(rounded(10.5, .heavy)).foregroundStyle(color).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) { bounces[i] = 0.78 }
                            DispatchQueue.main.async {
                                withAnimation(labSpring(0.42, 0.42)) { bounces[i] = 1 }
                            }
                            if router.tab != tab {
                                UISound.tap()
                                Haptics.tap()
                                router.tab = tab
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 7)
        .padding(.top, 7)
        .padding(.bottom, 9)
        .frame(height: 68)
        .background(
            LinearGradient(colors: tray, startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) {
                    // A lit top edge and a darker lip: the dock reads as a raised game tray.
                    LinearGradient(colors: [Color.white.opacity(lab.isDark ? 0.14 : 0.8), .clear], startPoint: .top, endPoint: .bottom).frame(height: 18)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color.black.opacity(lab.isDark ? 0.3 : 0.08)], startPoint: .top, endPoint: .bottom).frame(height: 12)
                }
        )
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(lab.isDark ? 0.3 : 0.95), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
        .labShadow(Color.black.opacity(0.45), 20, 8, 28)
        .frame(maxWidth: 540)
        .padding(.horizontal, 12)
    }
}

/// The selected tab's 3D key (drawn like a `GameKey` in purple).
private struct TabKey: View {
    var body: some View {
        let key = GameColors.purple
        let first = key[0], last = key[1]
        let faceTop = first.mix(.white, 0.18)
        let baseColor = last.mix(.black, 0.42)
        Canvas { ctx, full in
            let p: CGFloat = 14
            var ctx = ctx
            ctx.translateBy(x: p, y: p)
            let size = CGSize(width: full.width - p * 2, height: full.height - p * 2)
            let d: CGFloat = 4
            let h = size.height - d
            let r: CGFloat = 20
            ctx.shadowRoundRect(CGRect(x: 0, y: d, width: size.width, height: size.height - d), r, last.copy(alpha: 0.55), 10, 3)
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: d, width: size.width, height: h), cornerRadius: r), with: .color(baseColor))
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: h), cornerRadius: r),
                     with: .linearGradient(Gradient(colors: [faceTop, first, last]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            ctx.fill(Path(roundedRect: CGRect(x: size.width * 0.12, y: h * 0.06, width: size.width * 0.76, height: h * 0.4), cornerRadius: h * 0.2),
                     with: .linearGradient(Gradient(colors: [Color.white.opacity(0.5), .clear]), startPoint: CGPoint(x: 0, y: h * 0.05), endPoint: CGPoint(x: 0, y: h * 0.5)))
            ctx.stroke(Path(roundedRect: CGRect(x: 0.75, y: 0.75, width: size.width - 1.5, height: h - 1.5), cornerRadius: r),
                       with: .linearGradient(Gradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.1)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)),
                       lineWidth: 1.5)
        }
        .padding(-14)
        .allowsHitTesting(false)
    }
}
