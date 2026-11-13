import SwiftUI
import GameKit

/// Positions on the journey map. Every row has a fixed height, so any level's position is known.
final class JourneyLayout {
    enum Item {
        case world(Int)
        case chunk(ClosedRange<Int>, Int)

        var key: String {
            switch self {
            case .world(let i): return "world-\(i)"
            case .chunk(let r, _): return "chunk-\(r.lowerBound)"
            }
        }

        var height: CGFloat {
            switch self {
            case .world: return JourneyLayout.WORLD_CARD
            case .chunk(let r, _): return CGFloat(r.count) * JourneyLayout.RISE
            }
        }
    }

    static let RISE: CGFloat = 74
    static let WORLD_CARD: CGFloat = 150
    static let CHUNK = 25

    let worlds: [LevelMapTheme.World]
    let items: [Item]
    /// Top of each item (content coordinates, below the list's top padding).
    let tops: [CGFloat]
    let totalHeight: CGFloat

    init(_ worlds: [LevelMapTheme.World]) {
        self.worlds = worlds
        var items: [Item] = []
        for (index, world) in worlds.enumerated() {
            items.append(.world(index))
            var start = world.range.lowerBound
            while start <= world.range.upperBound {
                items.append(.chunk(start...min(start + JourneyLayout.CHUNK - 1, world.range.upperBound), index))
                start += JourneyLayout.CHUNK
            }
        }
        self.items = items
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for item in items {
            tops.append(y)
            y += item.height
        }
        self.tops = tops
        totalHeight = y
    }

    func worldIndex(_ level: Int) -> Int {
        if let i = worlds.firstIndex(where: { $0.range.contains(level) }) { return i }
        return max(0, worlds.count - 1)
    }

    /// Content offset that puts `level` about 40% down a `viewport`-tall screen.
    func scrollTarget(_ level: Int, _ viewport: CGFloat) -> CGFloat {
        let (index, within) = position(level)
        return max(0, tops.isEmpty ? 0 : tops[index] + within - viewport * 0.4)
    }

    /// The list index and offset inside it of a level's row.
    func position(_ level: Int) -> (Int, CGFloat) {
        guard let i = items.firstIndex(where: { if case .chunk(let r, _) = $0 { return r.contains(level) } else { return false } }),
              case .chunk(let r, _) = items[i] else { return (0, 0) }
        return (i, CGFloat(level - r.lowerBound) * JourneyLayout.RISE)
    }

    /// Horizontal position: a gentle S-curve, one swing every 10 levels.
    static func x(_ level: Int, _ width: CGFloat) -> CGFloat {
        let amplitude = min(width * 0.3, 128)
        return width / 2 + amplitude * CGFloat(sin(Double(level - 1) / 10.0 * 2 * .pi))
    }
}

/// The last win, animated once when the map reappears.
private enum JourneyMemory {
    static var seen: [String: Int] = [:]
}

/// A game's levels as a winding path through its worlds: done levels in the game's colours, the current
/// one glowing gold with the player's avatar on it, and the rest waiting in glass.
struct JourneyMapScreen: View {
    let module: any GameModule

    init(_ module: any GameModule) { self.module = module }

    @Environment(AppState.self) private var app
    @State private var compact: Bool?
    @State private var locked: Int?

    private var id: String { module.info.id }

    private func open(_ level: Int) {
        if app.store.progress(id).isUnlocked(level) {
            UISound.whoosh()
            app.router.push(.Play(id, level))
        } else {
            Haptics.warning()
            withAnimation(tween(200)) { locked = level }
        }
    }

    var body: some View {
        let isCompact = compact ?? Prefs.bool("map.compact.\(id)")
        let progress = app.store.progress(id)
        ZStack {
            if isCompact {
                CompactLevelGrid(module: module, onOpen: open) {
                    UISound.toggle()
                    withAnimation(tween(350)) { compact = false }
                    Prefs.putBool("map.compact.\(id)", false)
                }
                .transition(.opacity)
            } else {
                Journey(module: module, onOpen: open) {
                    UISound.toggle()
                    withAnimation(tween(350)) { compact = true }
                    Prefs.putBool("map.compact.\(id)", true)
                }
                .transition(.opacity)
            }
            if let level = locked {
                LockedLevelDialog(
                    level: level,
                    unlockAfter: progress.currentLevel,
                    module: module,
                    onWatchAd: {
                        Ads.rewarded.show("unlock_level") { granted in
                            guard granted else { return }
                            progress.unlockWithAd(level)
                            locked = nil
                            UISound.sparkle()
                            Haptics.success()
                            app.router.push(.Play(id, level))
                        }
                    },
                    onClose: { withAnimation(tween(180)) { locked = nil } },
                    canWatchAd: Ads.rewarded.isAvailable
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
    }
}

private struct Journey: View {
    let module: any GameModule
    let onOpen: (Int) -> Void
    let onCompact: () -> Void

    @Environment(AppState.self) private var app
    @State private var driver = ScrollDriver()
    @State private var box = JourneyBox()
    @State private var visible: ClosedRange<Int> = 0...0
    @State private var focusLevel: Int?
    @State private var celebrateFrom: Int?
    @State private var draw: Double = 1
    @State private var viewport: CGFloat = 700
    @State private var started = false

    private static let topPad: CGFloat = 132

    var body: some View {
        let theme = box.theme(module)
        let layout = box.layout(module)
        let progress = app.store.progress(module.info.id)
        let current = progress.currentLevel
        let focus = focusLevel ?? current
        let worldIndex = layout.worldIndex(focus)
        GeometryReader { geo in
            let width = min(geo.size.width, 560)
            ZStack(alignment: .top) {
                ZStack {
                    WorldBackdrop(world: theme.worlds.indices.contains(worldIndex) ? theme.worlds[worldIndex] : nil)
                        .id(worldIndex)
                        .transition(.opacity)
                }
                .animation(tween(600), value: worldIndex)
                DrivenScrollView(driver: driver, onOffset: { y in update(y, layout) }) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: Self.topPad)
                        ZStack(alignment: .top) {
                            ForEach(Array(visible), id: \.self) { i in
                                if layout.items.indices.contains(i) {
                                    itemView(layout.items[i], layout: layout, width: width, current: current)
                                        .frame(width: geo.size.width, height: layout.items[i].height)
                                        .offset(y: layout.tops[i])
                                }
                            }
                        }
                        .frame(width: geo.size.width, height: layout.totalHeight, alignment: .top)
                        Color.clear.frame(height: 150)
                    }
                    .frame(width: geo.size.width)
                }
                JourneyHeader(module: module, theme: theme, focusLevel: focus,
                              tint: theme.worlds.indices.contains(worldIndex) ? theme.worlds[worldIndex].top : nil,
                              onBack: { app.router.pop() }, onCompact: onCompact) { tier in
                    guard let start = module.catalog.range(tier)?.lowerBound else { return }
                    UISound.whoosh()
                    driver.scrollTo(y: layout.scrollTarget(start, 500), animated: true)
                }
                // Continue pill
                VStack {
                    Spacer()
                    let done = progress.isComplete
                    GameButton(done ? "All \(module.info.levelCount.grouped) levels done" : "Continue · Level \(current)",
                               icon: done ? Icons.Rounded.Verified : Icons.Rounded.PlayArrow, colors: GameColors.white, height: 58) {
                        if !done { onOpen(current) }
                    }
                    .padding(.bottom, 20)
                }
            }
            .onAppear {
                viewport = geo.size.height
                guard !started else { return }
                started = true
                let seen = JourneyMemoryAccess.seen(module.info.id)
                if let seen, current > seen, progress.isSolved(seen) {
                    celebrateFrom = seen
                    draw = 0
                }
                JourneyMemoryAccess.set(module.info.id, current)
                let y = layout.scrollTarget(current, 620)
                driver.scrollTo(y: y)
                update(y, layout)
                if celebrateFrom != nil {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        UISound.sparkle()
                        withAnimation(tween(600)) { draw = 1 }
                    }
                }
            }
            .onChange(of: geo.size.height) { _, h in viewport = h }
        }
    }

    /// Recomputes the rows to render and the world in focus from the scroll offset.
    private func update(_ y: CGFloat, _ layout: JourneyLayout) {
        let lo = y - Self.topPad - 500
        let hi = y - Self.topPad + viewport + 500
        var first = layout.items.count - 1, last = 0
        for (i, top) in layout.tops.enumerated() {
            let bottom = top + layout.items[i].height
            if bottom >= lo && top <= hi {
                first = min(first, i)
                last = max(last, i)
            }
        }
        let range = first <= last ? first...last : 0...0
        if range != visible { visible = range }
        // The first row whose bottom is below the header (≈ 126 pt under the status bar).
        var focus: Int?
        for (i, top) in layout.tops.enumerated() where Self.topPad + top + layout.items[i].height - y > 126 {
            switch layout.items[i] {
            case .chunk(let r, _): focus = r.lowerBound
            case .world(let w): focus = layout.worlds[w].range.lowerBound
            }
            break
        }
        if let focus, focus != focusLevel { focusLevel = focus }
    }

    @ViewBuilder
    private func itemView(_ item: JourneyLayout.Item, layout: JourneyLayout, width: CGFloat, current: Int) -> some View {
        let progress = app.store.progress(module.info.id)
        switch item {
        case .world(let index):
            let world = layout.worlds[index]
            WorldCard(index: index, world: world, solved: progress.solvedCount(world.range), stars: progress.stars(world.range))
        case .chunk(let range, let w):
            JourneyChunk(range: range, world: layout.worlds[w], width: width, module: module, current: current,
                         celebrateFrom: celebrateFrom, draw: draw, onTap: onOpen)
        }
    }
}

/// The map theme and its layout, built once per screen (a game's `mapTheme` may decode its pack).
private final class JourneyBox {
    private var cachedTheme: LevelMapTheme?
    private var cachedLayout: JourneyLayout?

    func theme(_ module: any GameModule) -> LevelMapTheme {
        if let t = cachedTheme { return t }
        let t = module.mapTheme
        cachedTheme = t
        return t
    }

    func layout(_ module: any GameModule) -> JourneyLayout {
        if let l = cachedLayout { return l }
        let l = JourneyLayout(theme(module).worlds)
        cachedLayout = l
        return l
    }
}

private enum JourneyMemoryAccess {
    static func seen(_ id: String) -> Int? { JourneyMemory.seen[id] }
    static func set(_ id: String, _ level: Int) { JourneyMemory.seen[id] = level }
}

private struct WorldBackdrop: View {
    let world: LevelMapTheme.World?

    var body: some View {
        if let world {
            LinearGradient(colors: [world.top, world.bottom], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .topTrailing) {
                    Icon(world.motif, tint: Color.white.opacity(world.isDark ? 0.05 : 0.18), size: 260)
                        .rotationEffect(.degrees(-12))
                        .offset(x: 70, y: 180)
                }
                .overlay(alignment: .bottomLeading) {
                    Circle()
                        .fill(RadialGradient(colors: [world.accent.copy(alpha: 0.22), world.accent.copy(alpha: 0.1), .clear], center: .center, startRadius: 0, endRadius: 270))
                        .frame(width: 540, height: 540)
                        .offset(x: -120 + 180 - 270, y: 120 - 180 + 270)
                }
                .clipped()
                .ignoresSafeArea()
        } else {
            Color.clear
        }
    }
}

/// A simple wrapping row (Compose `FlowRow`).
struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > bounds.width {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y + 0), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

private struct JourneyHeader: View {
    let module: any GameModule
    let theme: LevelMapTheme
    let focusLevel: Int
    let tint: Color?
    let onBack: () -> Void
    let onCompact: () -> Void
    let onJump: (DifficultyTier) -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let progress = app.store.progress(module.info.id)
        let tiers = module.catalog.tiers
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GameBackButton(onClick: onBack)
                // With a coin pill there is no room for the badge next to 4-digit progress.
                if theme.coins == nil {
                    GameBadgeFrame(module.info.colors, 40, glow: false) { module.BadgeArt(32) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.info.name).font(rounded(16, .heavy)).foregroundStyle(Color.white).lineLimit(1).truncationMode(.tail)
                    FlowRow(spacing: 4) {
                        Text("\(progress.solvedCount.grouped)/\(progress.levelCount.grouped)")
                            .font(rounded(12, .bold)).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1).fixedSize()
                        HStack(spacing: 4) {
                            Icon(Icons.Rounded.Star, tint: lab.sun, size: 12)
                            Text(progress.totalStars.grouped).font(rounded(12, .bold)).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1).fixedSize()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let coins = theme.coins {
                    StatPill(Icons.Rounded.MonetizationOn, coins().grouped)
                }
                GlassIconButton(Icons.Rounded.Apps, tint: .white, onClick: onCompact)
            }
            if tiers.count > 1 {
                let focusTier = module.catalog.tier(focusLevel) ?? tiers[0]
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tiers, id: \.self) { tier in
                            let selected = tier == focusTier
                            let c = selected ? hex(0x14112E) : Color.white
                            HStack(spacing: 5) {
                                Icon(tierIcon(tier), tint: c, size: 15)
                                if selected { Text(tier.title).font(rounded(13, .heavy)).foregroundStyle(c) }
                            }
                            .padding(.horizontal, 13)
                            .frame(height: 32)
                            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.white.opacity(0.18), lineWidth: 1))
                            .pressable(0.92) {
                                if !selected {
                                    Haptics.tap()
                                    onJump(tier)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            (tint ?? lab.bgBottom).mix(.black, 0.18).copy(alpha: 0.94)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1 / UIScreen.main.scale) }
                .ignoresSafeArea(edges: .top)
        )
    }
}

private struct WorldCard: View {
    let index: Int
    let world: LevelMapTheme.World
    let solved: Int
    let stars: Int

    var body: some View {
        let ink = world.isDark ? Color.white : hex(0x1C1B29)
        let shape = RoundedRectangle(cornerRadius: Lab.Radius.bigCard, style: .circular)
        HStack(spacing: 12) {
            Icon(world.motif, tint: .white, size: 26)
                .frame(width: 52, height: 52)
                .background(Circle().fill(LinearGradient(colors: [world.accent, world.accent.mix(.black, 0.3)], startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 4) {
                Text("WORLD \(index + 1)").font(rounded(11, .heavy)).tracking(1.4).foregroundStyle(ink.opacity(0.75))
                Text(world.name).font(rounded(20, .black)).foregroundStyle(ink).lineLimit(1)
                HStack(spacing: 8) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ink.opacity(0.18))
                            Capsule().fill(world.accent).frame(width: max(8, g.size.width * CGFloat(solved) / CGFloat(max(world.range.count, 1))))
                        }
                    }
                    .frame(height: 8)
                    Text("\(solved) / \(world.range.count)").font(rounded(12, .heavy)).foregroundStyle(ink.opacity(0.85)).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if stars > 0 {
                Icon(Icons.Rounded.Star, tint: ink, size: 14)
                Text("\(stars)").font(rounded(13, .heavy)).foregroundStyle(ink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Color.white.opacity(world.isDark ? 0.12 : 0.5)))
        .overlay(shape.strokeBorder(Color.white.opacity(world.isDark ? 0.2 : 0.7), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: 560)
    }
}

private enum NodeState { case Done, Current, Next, Locked }

/// Up to 25 levels of the path: a canvas for the path, then the nodes.
private struct JourneyChunk: View {
    let range: ClosedRange<Int>
    let world: LevelMapTheme.World
    let width: CGFloat
    let module: any GameModule
    let current: Int
    let celebrateFrom: Int?
    let draw: Double
    let onTap: (Int) -> Void

    @Environment(AppState.self) private var app

    private func pt(_ level: Int) -> CGPoint {
        CGPoint(x: JourneyLayout.x(level, width), y: CGFloat(level - range.lowerBound) * JourneyLayout.RISE + JourneyLayout.RISE / 2)
    }

    var body: some View {
        let progress = app.store.progress(module.info.id)
        let rise = JourneyLayout.RISE
        let pathFrom = max(range.lowerBound - 1, world.range.lowerBound)
        let pathTo = min(range.upperBound + 1, world.range.upperBound)
        let accent = world.accent
        let dark = world.isDark
        let lo = range.lowerBound
        let w = width
        let cur = current
        let cel = celebrateFrom
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                func p(_ level: Int) -> CGPoint {
                    CGPoint(x: JourneyLayout.x(level, w), y: CGFloat(level - lo) * rise + rise / 2)
                }
                if pathFrom < pathTo {
                    for level in pathFrom..<pathTo {
                        let a = p(level), b = p(level + 1)
                        var seg = Path()
                        seg.move(to: a)
                        seg.addCurve(to: b, control1: CGPoint(x: a.x, y: a.y + rise / 2), control2: CGPoint(x: b.x, y: b.y - rise / 2))
                        let celebrating = cel != nil && level + 1 == cur && level == cel
                        if level + 1 <= cur && !celebrating {
                            ctx.stroke(seg, with: .color(accent.copy(alpha: 0.5)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            ctx.stroke(seg, with: .color(Color.white.opacity(0.9)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        } else {
                            ctx.stroke(seg, with: .color(Color.white.opacity(dark ? 0.45 : 0.85)),
                                       style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.5, 11]))
                        }
                    }
                }
            }
            .frame(width: width, height: CGFloat(range.count) * rise)
            if let cel, cel + 1 == cur, cel >= pathFrom, cel < pathTo {
                CelebrateSegment(a: pt(cel), b: pt(cel + 1), rise: rise)
                    .trim(from: 0, to: draw)
                    .stroke(accent.copy(alpha: 0.5), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: width, height: CGFloat(range.count) * rise)
                CelebrateSegment(a: pt(cel), b: pt(cel + 1), rise: rise)
                    .trim(from: 0, to: draw)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: width, height: CGFloat(range.count) * rise)
                    .opacity(draw > 0 ? 1 : 0)
            }
            ForEach(Array(range), id: \.self) { level in
                let state: NodeState = {
                    if progress.isSolved(level) { return .Done }
                    if level == current { return .Current }
                    if progress.isUnlocked(level) || level <= current + 3 { return .Next }
                    return .Locked
                }()
                let p = pt(level)
                let hop: CGPoint? = {
                    guard let cel, level == current, draw < 1 else { return nil }
                    let from = pt(cel)
                    return CGPoint(x: from.x - p.x, y: from.y - p.y)
                }()
                JourneyNode(level: level, state: state, stars: progress.record(level)?.stars ?? 0, module: module, isDarkWorld: world.isDark,
                            adUnlocked: progress.isAdUnlocked(level) && !progress.isSolved(level),
                            avatarOnRight: JourneyLayout.x(level, width) >= JourneyLayout.x(level - 1, width),
                            hopFrom: celebrateFrom != nil && level == current ? hop ?? .zero : nil,
                            draw: draw,
                            starsPop: celebrateFrom == level) { onTap(level) }
                    .position(x: p.x, y: p.y)
            }
        }
        .frame(width: width, height: CGFloat(range.count) * rise)
    }
}

private struct CelebrateSegment: Shape {
    let a: CGPoint
    let b: CGPoint
    let rise: CGFloat

    func path(in rect: CGRect) -> Path {
        var seg = Path()
        seg.move(to: a)
        seg.addCurve(to: b, control1: CGPoint(x: a.x, y: a.y + rise / 2), control2: CGPoint(x: b.x, y: b.y - rise / 2))
        return seg
    }
}

private struct JourneyNode: View {
    let level: Int
    let state: NodeState
    let stars: Int
    let module: any GameModule
    let isDarkWorld: Bool
    let adUnlocked: Bool
    let avatarOnRight: Bool
    /// Offset from the previous node while the avatar hops over (celebration), else nil.
    let hopFrom: CGPoint?
    let draw: Double
    let starsPop: Bool
    let onTap: () -> Void

    @Environment(AppState.self) private var app
    @State private var starScale: CGFloat = 1

    var body: some View {
        let lab = Lab.colors
        let size: CGFloat = state == .Current ? 66 : 54
        let reduce = Lab.reduceMotion
        ZStack {
            NodeDisc(state: state, colors: module.info.colors, first: module.info.first, isDarkWorld: isDarkWorld, size: size, pulse: state == .Current && !reduce)
            if state == .Locked {
                Icon(Icons.Rounded.Lock, tint: (isDarkWorld ? Color.white : hex(0x1C1B29)).opacity(0.45), size: 16)
            } else {
                let color: Color = state == .Current ? hex(0x5A3200) : (state == .Done ? .white : (isDarkWorld ? .white : hex(0x1C1B29)))
                Text("\(level)").font(rounded(level >= 1000 ? 15 : 19, .black)).foregroundStyle(color).lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if level % 25 == 0 {
                Icon(Icons.Rounded.EmojiEvents, tint: hex(0x6B4300), size: 12)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(lab.sun))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .offset(x: 4, y: -4)
            }
        }
        .overlay(alignment: .topLeading) {
            if adUnlocked {
                Icon(Icons.Rounded.Key, tint: .white, size: 12)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(lab.ok))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .offset(x: -4, y: -4)
            }
        }
        .overlay(alignment: .bottom) {
            if state == .Done && stars > 0 {
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { i in
                        Icon(Icons.Rounded.Star, tint: i < stars ? lab.sun : Color.black.opacity(0.25), size: i == 1 ? 15 : 13)
                            .offset(y: i == 1 ? 2 : 0)
                    }
                }
                .scaleEffect(starScale)
                .offset(y: 14)
            }
        }
        .pressable(0.9, onClick: onTap)
        .overlay(alignment: avatarOnRight ? .topTrailing : .topLeading) {
            if state == .Current {
                let hop = hopFrom ?? .zero
                ProfileAvatar(app.profile.avatar, profileColor(app.profile.colorIndex), 38)
                    .floating(3)
                    .offset(x: (avatarOnRight ? 30 : -30) + hop.x * (1 - draw), y: -22 + hop.y * (1 - draw))
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            guard starsPop, !Lab.reduceMotion else { return }
            starScale = 0.1
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(labSpring(0.42, 0.6)) { starScale = 1 }
            }
        }
    }
}

/// The node's disc. Only the current node animates (its halo pulses), in a timeline of its own.
private struct NodeDisc: View {
    let state: NodeState
    let colors: [Color]
    let first: Color
    let isDarkWorld: Bool
    let size: CGFloat
    let pulse: Bool

    var body: some View {
        if state == .Current && pulse {
            TimelineView(.animation) { tl in
                // 1200 ms FastOutSlowIn, reversing.
                let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 1.2
                let lin = t <= 1 ? t : 2 - t
                discCanvas(fastOutSlowIn(lin))
            }
        } else {
            discCanvas(0)
        }
    }

    private func discCanvas(_ pulse: Double) -> some View {
        let pad: CGFloat = size * 0.5
        let state = self.state, colors = self.colors, first = self.first, dark = isDarkWorld
        return Canvas { ctx, s in
            _ = pulse
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let r = size / 2
            func circle(_ radius: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)) }
            let box = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            switch state {
            case .Done:
                ctx.shadowRoundRect(box, r, first.copy(alpha: 0.5), 16, 4)
                ctx.fill(circle(r), with: .linearGradient(Gradient(colors: colors), startPoint: box.origin, endPoint: CGPoint(x: box.maxX, y: box.maxY)))
                ctx.fill(circle(r - 4), with: .linearGradient(Gradient(colors: [Color.white.opacity(0.4), .clear]),
                                                              startPoint: CGPoint(x: 0, y: box.minY + 4), endPoint: CGPoint(x: 0, y: c.y)))
                ctx.stroke(circle(r - 1.5), with: .color(.white), lineWidth: 3)
            case .Current:
                let gold = hex(0xFFD35A)
                ctx.stroke(circle(r * (1.05 + 0.5 * pulse)), with: .color(gold.copy(alpha: 0.7 * (1 - pulse))), lineWidth: 3)
                ctx.stroke(circle(r * (1.06 + 0.22 * pulse)), with: .color(gold.copy(alpha: 0.5 - 0.35 * pulse)), lineWidth: 2)
                ctx.shadowRoundRect(box, r, hex(0xFFB020).copy(alpha: 0.7), 32, 4)
                ctx.fill(circle(r), with: .linearGradient(Gradient(colors: [hex(0xFFE38A), hex(0xFFC23D), hex(0xF08A1C)]),
                                                          startPoint: CGPoint(x: 0, y: box.minY), endPoint: CGPoint(x: 0, y: box.maxY)))
                ctx.fill(circle(r - 5), with: .linearGradient(Gradient(colors: [Color.white.opacity(0.55), .clear]),
                                                              startPoint: CGPoint(x: 0, y: box.minY + 5), endPoint: CGPoint(x: 0, y: c.y)))
                ctx.stroke(circle(r - 1.75), with: .color(.white), lineWidth: 3.5)
            case .Next:
                ctx.fill(circle(r), with: .color(Color.white.opacity(dark ? 0.2 : 0.65)))
                ctx.stroke(circle(r - 1), with: .color(Color.white.opacity(0.75)), lineWidth: 2)
            case .Locked:
                ctx.fill(circle(r), with: .color(Color.white.opacity(dark ? 0.08 : 0.35)))
                ctx.stroke(circle(r - 0.75), with: .color(Color.white.opacity(dark ? 0.22 : 0.5)), lineWidth: 1.5)
            }
        }
        .frame(width: size + pad * 2, height: size + pad * 2)
        .padding(-pad)
        .allowsHitTesting(false)
    }
}

/// Compose `FastOutSlowInEasing` (cubic-bezier 0.4, 0, 0.2, 1) evaluated at `x`.
func fastOutSlowIn(_ x: Double) -> Double { cubicBezier(x, 0.4, 0, 0.2, 1) }

func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    var lo = 0.0, hi = 1.0, t = x
    for _ in 0..<24 {
        let cx = 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t
        if cx < x { lo = t } else { hi = t }
        t = (lo + hi) / 2
    }
    return 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t
}

// MARK: - Compact grid

/// Every level in blocks of 25: a grid for jumping straight to a level.
private struct CompactLevelGrid: View {
    let module: any GameModule
    let onOpen: (Int) -> Void
    let onJourney: () -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let progress = app.store.progress(module.info.id)
        let count = module.catalog.count
        let current = progress.currentLevel
        let blocks: [ClosedRange<Int>] = count > 0 ? stride(from: 1, through: count, by: 25).map { $0...min($0 + 24, count) } : []
        ZStack(alignment: .top) {
            LabBackground()
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        HStack(spacing: 12) {
                            GameBadgeFrame(module.info.colors, 56, glow: false) { module.BadgeArt(45) }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(module.info.name).font(rounded(20, .black)).foregroundStyle(Color.white)
                                Text("\(progress.solvedCount.grouped) of \(count.grouped) solved").font(rounded(13, .bold)).foregroundStyle(Color.white.opacity(0.85))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if !progress.isComplete {
                                GameButton("Level \(current)", icon: Icons.Rounded.PlayArrow, colors: GameColors.white, height: 44, fontSize: 15) { onOpen(current) }
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 26, style: .circular).fill(module.info.gradient))
                        .labShadow(module.info.first.copy(alpha: 0.4), 16, 8, 26)
                        .id("header")
                        ForEach(blocks, id: \.lowerBound) { block in
                            BlockCard(module: module, block: block, current: current, onOpen: onOpen)
                                .id("block-\(block.lowerBound)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 76)
                    .padding(.bottom, 40)
                }
                .onAppear {
                    // Kotlin scrolls to the list item at the block's index (the header is item 0).
                    let k = max(0, blocks.firstIndex { $0.contains(current) } ?? 0)
                    let target = k == 0 ? "header" : "block-\(blocks[k - 1].lowerBound)"
                    DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
                }
            }
            HStack(spacing: 0) {
                GameBackButton { app.router.pop() }
                Text(module.info.name).font(LabText.headline).foregroundStyle(lab.ink).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                GlassIconButton(Icons.Rounded.Map, onClick: onJourney)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(lab.bgBottom.copy(alpha: 0.8).ignoresSafeArea(edges: .top))
        }
    }
}

private struct BlockCard: View {
    let module: any GameModule
    let block: ClosedRange<Int>
    let current: Int
    let onOpen: (Int) -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let progress = app.store.progress(module.info.id)
        let tier = module.catalog.tier(block.lowerBound)
        let rows: [[Int]] = stride(from: block.lowerBound, through: block.upperBound, by: 5).map { Array($0...min($0 + 4, block.upperBound)) }
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text("Levels \(block.lowerBound)–\(block.upperBound)").font(rounded(16, .heavy)).foregroundStyle(lab.ink)
                let label = module.catalog.sizeLabel(block.lowerBound)
                if !label.isEmpty, let tier {
                    Text(label).font(rounded(11, .heavy)).foregroundStyle(tierColor(tier, lab))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(tierColor(tier, lab).copy(alpha: 0.18)))
                }
                Spacer(minLength: 0)
                Text("\(progress.solvedCount(block))/\(block.count)").font(rounded(13, .heavy)).foregroundStyle(lab.ink2)
            }
            ForEach(rows, id: \.first) { row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element) { i, level in
                        if i > 0 { Spacer(minLength: 0) }
                        GridNode(module: module, level: level, current: current, onOpen: onOpen)
                    }
                    ForEach(row.count..<5, id: \.self) { _ in
                        Spacer(minLength: 0)
                        Color.clear.frame(width: 52, height: 52)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .labGlass(Lab.Radius.bigCard)
    }
}

private struct GridNode: View {
    let module: any GameModule
    let level: Int
    let current: Int
    let onOpen: (Int) -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let progress = app.store.progress(module.info.id)
        let solved = progress.isSolved(level)
        let unlocked = progress.isUnlocked(level)
        let isCurrent = level == current && !solved
        let stars = progress.record(level)?.stars ?? 0
        VStack(spacing: 0) {
            ZStack {
                GridDisc(solved: solved, isCurrent: isCurrent, unlocked: unlocked, pulse: isCurrent && !Lab.reduceMotion)
                if !unlocked {
                    Icon(Icons.Rounded.Lock, tint: lab.ink2.copy(alpha: 0.6), size: 14)
                } else {
                    Text("\(level)").font(rounded(level >= 100 ? 15 : 18, .black)).foregroundStyle(solved || isCurrent ? Color.white : lab.ink).lineLimit(1)
                }
            }
            .frame(width: 52, height: 52)
            .pressable(0.9) { onOpen(level) }
            HStack(spacing: 0) {
                if solved {
                    ForEach(0..<3, id: \.self) { i in
                        Icon(Icons.Rounded.Star, tint: i < stars ? lab.sun : lab.ink2.copy(alpha: 0.3), size: 10)
                    }
                }
            }
            .frame(height: 12)
        }
    }
}

private struct GridDisc: View {
    let solved: Bool
    let isCurrent: Bool
    let unlocked: Bool
    let pulse: Bool

    var body: some View {
        if pulse {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 1.2
                disc(fastOutSlowIn(t <= 1 ? t : 2 - t))
            }
        } else {
            disc(0)
        }
    }

    private func disc(_ pulse: Double) -> some View {
        let lab = Lab.colors
        let solved = self.solved, isCurrent = self.isCurrent, unlocked = self.unlocked
        return Canvas { ctx, s in
            _ = pulse
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let r: CGFloat = 26
            func circle(_ radius: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)) }
            let box = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            if solved {
                ctx.fill(circle(r), with: .linearGradient(Gradient(colors: [lab.ok.mix(.white, 0.15), lab.ok]), startPoint: box.origin, endPoint: CGPoint(x: box.maxX, y: box.maxY)))
            } else if isCurrent {
                ctx.stroke(circle(r * (1.05 + 0.25 * pulse)), with: .color(lab.brand2.copy(alpha: 0.35 * (1 - pulse))), lineWidth: 4)
                ctx.fill(circle(r), with: .linearGradient(Gradient(colors: [lab.paletteBrand, lab.paletteBrandEnd]), startPoint: box.origin, endPoint: CGPoint(x: box.maxX, y: box.maxY)))
                ctx.stroke(circle(r - 1.5), with: .color(Color.white.opacity(0.85)), lineWidth: 3)
            } else if unlocked {
                ctx.fill(circle(r), with: .color(lab.glass))
                ctx.stroke(circle(r - 0.75), with: .color(lab.glassStroke), lineWidth: 1.5)
            } else {
                ctx.fill(circle(r), with: .color(Color.black.opacity(lab.isDark ? 0.22 : 0.06)))
            }
        }
        .frame(width: 52 + 30, height: 52 + 30)
        .padding(-15)
        .allowsHitTesting(false)
    }
}

// MARK: - Locked level

/// "Level N is locked": finish the previous level, or jump ahead now through the rewarded-ad seam.
struct LockedLevelDialog: View {
    let level: Int
    let unlockAfter: Int
    let module: any GameModule
    let onWatchAd: () -> Void
    let onClose: () -> Void
    var canWatchAd: Bool = true

    init(level: Int, unlockAfter: Int, module: any GameModule, onWatchAd: @escaping () -> Void, onClose: @escaping () -> Void, canWatchAd: Bool = true) {
        self.level = level
        self.unlockAfter = unlockAfter
        self.module = module
        self.onWatchAd = onWatchAd
        self.onClose = onClose
        self.canWatchAd = canWatchAd
    }

    @State private var appear = false
    @State private var bounce: CGFloat = 1

    var body: some View {
        let lab = Lab.colors
        let info = module.info
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    GameIconButton(Icons.Rounded.Close, colors: GameColors.slate(), size: 36, iconSize: 18, onClick: onClose)
                }
                Icon(Icons.Rounded.Lock, tint: .white, size: 36)
                    .scaleEffect(bounce)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(info.gradient))
                    .labShadow(info.first.copy(alpha: 0.45), 14, 8, circle: true)
                    .offset(y: -18)
                VStack(spacing: 6) {
                    Text("Level \(level) is locked").font(gameTextStyle(26)).foregroundStyle(lab.ink).multilineTextAlignment(.center)
                    Text(canWatchAd ? "Finish level \(unlockAfter) to unlock it, or jump ahead now." : "Finish level \(unlockAfter) to unlock it.")
                        .font(rounded(15, .semibold)).foregroundStyle(lab.inkSecondary).multilineTextAlignment(.center)
                }
                .offset(y: -12)
                if canWatchAd {
                    LabPrimaryButton(Ads.usesRealAds ? "Watch ad to play" : "Play FREE", icon: Icons.Rounded.SmartDisplay, colors: info.colors, height: 58) {
                        Haptics.cta()
                        onWatchAd()
                    }
                } else {
                    LabPrimaryButton("Got it", colors: info.colors, height: 58) { onClose() }
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .gamePopup(32, info.colors)
            .contentShape(Rectangle())
            .onTapGesture {}
            .padding(.horizontal, 28)
            .opacity(appear ? 1 : 0)
            .scaleEffect(appear ? 1 : 0.86)
        }
        .task {
            withAnimation(labSpring(0.42, 0.72)) { appear = true }
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(tween(120)) { bounce = 1.2 }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(labSpring(0.42, 0.45)) { bounce = 1 }
        }
    }
}

/// "Watch a video for coins" offer behind the coin pill's "+": grants through `Ads.rewarded`
/// (instantly while no ad network is configured; labelled FREE then).
func offerCoins(_ amount: Int, _ onEarn: @escaping (Int) -> Void) {
    mainActorRun {
        let free = !Ads.usesRealAds
        PromptCenter.show(
            LabPrompt(
                Icons.Rounded.SmartDisplay, hex(0x34D399), "Free coins",
                free ? "Get +\(amount) coins for free." : "Watch a short video for +\(amount) coins.",
                choices: [
                    LabPrompt.Choice(free ? "Get FREE" : "Watch video", .Primary, Icons.Rounded.SmartDisplay) {
                        mainActorRun {
                            Ads.rewarded.show("coins") { granted in
                                guard granted else { return }
                                onEarn(amount)
                                UISound.sparkle()
                                Haptics.success()
                            }
                        }
                    },
                    LabPrompt.Choice("Not now", .Cancel),
                ]
            )
        )
    }
}

func offerCoins(amount: Int, onEarn: @escaping (Int) -> Void) { offerCoins(amount, onEarn) }

/// Runs `body` on the main actor now when already on the main thread, else as soon as possible.
func mainActorRun(_ body: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { body() }
    } else {
        Task { @MainActor in body() }
    }
}
