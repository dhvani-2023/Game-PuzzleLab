import SwiftUI

/// The big title at the top of a tab.
struct TabHeader: View {
    let title: String
    var subtitle: String? = nil

    init(_ title: String, _ subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        let lab = Lab.colors
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(gameTextStyle(34)).foregroundStyle(lab.ink)
            if let subtitle { Text(subtitle).font(LabText.caption).foregroundStyle(lab.ink2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

private enum Filter: CaseIterable {
    case All, Puzzle, Logic

    var title: String {
        switch self {
        case .All: return "All"
        case .Puzzle: return "Puzzle"
        case .Logic: return "Logic"
        }
    }

    var icon: ImageVector {
        switch self {
        case .All: return Icons.Rounded.GridView
        case .Puzzle: return Icons.Rounded.Extension
        case .Logic: return Icons.Rounded.Psychology
        }
    }

    func includes(_ category: String) -> Bool {
        switch self {
        case .All: return true
        case .Puzzle: return category == "Puzzle"
        case .Logic: return category == "Logic" || category == "Path"
        }
    }
}

struct GamesTab: View {
    let bottomInset: CGFloat

    init(_ bottomInset: CGFloat) { self.bottomInset = bottomInset }

    @Environment(AppState.self) private var app
    @State private var filter: Filter = .All

    var body: some View {
        let filters = Filter.allCases.filter { f in f == .All || GameRegistry.games.contains { f.includes($0.info.category) } }
        let games = GameRegistry.games.filter { filter.includes($0.info.category) }
        let rows: [[any GameModule]] = stride(from: 0, to: games.count, by: 2).map { Array(games[$0..<min($0 + 2, games.count)]) }
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                Appear(0) {
                    let levels = GameRegistry.totalLevels / 100 * 100
                    TabHeader("Games", "\(GameRegistry.games.count) puzzle games · \(levels.grouped)+ levels")
                }
                Appear(1) {
                    VStack(spacing: 16) {
                        ChipBar(filters: filters, selection: filter) { filter = $0 }
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(row, id: \.info.id) { module in
                                    GameTile(module: module) { app.router.openLevels(module) }
                                }
                                if row.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, bottomInset + 24)
        }
    }
}

private struct ChipBar: View {
    let filters: [Filter]
    let selection: Filter
    let onSelect: (Filter) -> Void

    var body: some View {
        let slate = GameColors.slate()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filters, id: \.self) { f in
                    let selected = f == selection
                    let face = selected ? GameColors.purple : slate
                    let ink = GameColors.ink(face)
                    GameKey(colors: face, corner: 20, depth: 4, onClick: { if !selected { onSelect(f) } }) {
                        HStack(spacing: 6) {
                            Icon(f.icon, tint: ink, size: 18)
                            if selected {
                                Text(f.title).font(gameTextStyle(15, (face.last ?? .black).mix(.black, 0.45).copy(alpha: 0.6))).foregroundStyle(ink)
                            } else {
                                Text(f.title).font(rounded(15, .heavy)).foregroundStyle(ink)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 44)
                }
            }
            .padding(.vertical, 2)
            .padding(.bottom, 4)
        }
        .scrollClipDisabled()
    }
}

private struct GameTile: View {
    let module: any GameModule
    let onClick: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let progress = app.store.progress(module.info.id)
        let fraction = Double(progress.solvedCount) / Double(max(progress.levelCount, 1))
        VStack(spacing: 8) {
            GameBadgeFrame(module.info.colors, 96) { module.BadgeArt(77) }
                .overlay(alignment: .topTrailing) {
                    if progress.solvedCount > 0 {
                        ProgressRing(max(fraction, 0.06), 3, Color.white.opacity(0.3), Color.white)
                            .padding(4)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(module.info.last))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
                            .offset(x: 10, y: -10)
                    }
                }
            Spacer().frame(height: 2)
            Text(module.info.name).font(gameTextStyle(20)).foregroundStyle(lab.ink).lineLimit(1)
            Text(progress.solvedCount > 0 ? "\(progress.solvedCount.grouped)/\(progress.levelCount.grouped)" : "\(module.info.levelCount.grouped) levels")
                .font(rounded(15, .bold)).foregroundStyle(lab.ink2)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .labGlass(Lab.Radius.bigCard)
        .pressable(0.96) {
            UISound.whoosh()
            onClick()
        }
    }
}

// MARK: - Progress

struct ProgressTab: View {
    let bottomInset: CGFloat

    init(_ bottomInset: CGFloat) { self.bottomInset = bottomInset }

    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let store = app.store
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                Appear(0) { TabHeader("Progress", "Everything stays on this device") }
                Appear(1) { LevelCard() }
                Appear(2) {
                    VStack(spacing: 12) {
                        SectionHeader("This week")
                        WeeklyStatsCard()
                    }
                }
                Appear(3) {
                    VStack(spacing: 12) {
                        SectionHeader("By game")
                        VStack(spacing: 8) {
                            ForEach(GameRegistry.games, id: \.info.id) { module in
                                let progress = store.progress(module.info.id)
                                let fraction = CGFloat(progress.solvedCount) / CGFloat(max(progress.levelCount, 1))
                                HStack(spacing: 12) {
                                    GameBadgeFrame(module.info.colors, 46, glow: false) { module.BadgeArt(37) }
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 0) {
                                            Text(module.info.name).font(LabText.cardTitle).foregroundStyle(lab.ink).frame(maxWidth: .infinity, alignment: .leading)
                                            Icon(Icons.Rounded.Star, tint: lab.sun, size: 13)
                                            Text(" \(progress.totalStars)").font(rounded(12, .heavy)).foregroundStyle(lab.sun)
                                        }
                                        GeometryReader { g in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(lab.ink2.copy(alpha: 0.18))
                                                Capsule().fill(module.info.gradient)
                                                    .frame(width: progress.solvedCount > 0 ? max(6, g.size.width * fraction) : 0)
                                            }
                                        }
                                        .frame(height: 7)
                                        Text(progress.solvedCount == 0 ? "Not started · \(progress.levelCount.grouped) levels"
                                             : "\(progress.solvedCount.grouped) of \(progress.levelCount.grouped) levels")
                                            .font(LabText.caption).foregroundStyle(lab.ink2)
                                    }
                                }
                                .padding(12)
                                .labGlass(Lab.Radius.card)
                                .pressable(0.98) { app.router.openLevels(module) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, bottomInset + 24)
        }
    }
}

private struct LevelCard: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let store = app.store
        let xp = store.labXP
        let level = LabLevel.level(xp)
        let next = LabLevel.threshold(level + 1)
        let shape = RoundedRectangle(cornerRadius: Lab.Radius.hero, style: .circular)
        HStack(spacing: 16) {
            LabLevelAvatar(76)
            VStack(alignment: .leading, spacing: 4) {
                Text("Lab level \(level)").font(rounded(24, .black)).foregroundStyle(Color.white)
                Text("\(xp.grouped) XP · \((next - xp).grouped) to level \(level + 1)").font(rounded(13, .bold)).foregroundStyle(Color.white.opacity(0.85))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule().fill(LinearGradient(colors: [lab.sun, hex(0xFF8A3D)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, g.size.width * CGFloat(LabLevel.progress(xp))))
                    }
                }
                .frame(height: 8)
                HStack(spacing: 12) {
                    MiniLabel(value: store.totalSolved.grouped, label: "solved", icon: Icons.Rounded.Verified)
                    MiniLabel(value: store.totalStars.grouped, label: "stars", icon: Icons.Rounded.Star)
                    MiniLabel(value: "\(store.bestStreak)", label: "day best", icon: Icons.Rounded.LocalFireDepartment)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(lab.brandGradient)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .labShadow(lab.brand.copy(alpha: 0.4), 20, 10, Lab.Radius.hero)
    }
}

private struct MiniLabel: View {
    let value: String
    let label: String
    let icon: ImageVector

    var body: some View {
        HStack(spacing: 3) {
            Icon(icon, tint: .white, size: 12)
            Text(value).font(rounded(12, .heavy)).foregroundStyle(Color.white)
            Text(label).font(rounded(11, .bold)).foregroundStyle(Color.white).lineLimit(1)
        }
        .fixedSize()
    }
}

/// Streak, this week's play days and overall progress in one card.
private struct WeeklyStatsCard: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let store = app.store
        let today = Days.dayNumber()
        let weekStart = today - Days.weekdayIndex(today)
        let playedToday = store.didPlay(today)
        let message: String = store.streak == 0 ? "Solve any puzzle to start a streak"
            : (playedToday ? "You're on fire — see you tomorrow" : "Solve one today to keep it going")
        let flame = LinearGradient(colors: [lab.sun, lab.patch(0)], startPoint: .top, endPoint: .bottom)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let total = GameRegistry.totalLevels
        let value = Double(store.totalSolved) / Double(max(total, 1))
        let pct = value * 100
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Icon(Icons.Rounded.LocalFireDepartment, tint: .white, size: 28)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(flame))
                    .labShadow(lab.patch(0).copy(alpha: 0.4), 10, 5, circle: true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text("\(store.streak)").font(rounded(28, .heavy)).foregroundStyle(lab.ink)
                        Text("day streak").font(rounded(16, .heavy)).foregroundStyle(lab.ink)
                    }
                    Text(message).font(rounded(13, .semibold)).foregroundStyle(lab.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 0) {
                    Text("\(store.bestStreak)").font(rounded(18, .heavy)).foregroundStyle(lab.ink)
                    Text("BEST").font(rounded(9, .heavy)).tracking(1).foregroundStyle(lab.ink2)
                }
                .frame(width: 50, height: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .circular).fill(lab.glass))
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let day = weekStart + i
                    let played = store.didPlay(day)
                    let isToday = day == today
                    let future = day > today
                    VStack(spacing: 7) {
                        Text(letters[i]).font(rounded(11, .heavy)).foregroundStyle(isToday ? lab.ink : lab.ink2)
                        ZStack {
                            if played {
                                Circle().fill(flame)
                            } else {
                                Circle().fill(lab.glass.copy(alpha: lab.glassAlpha * (future ? 0.5 : 1)))
                            }
                            if isToday && !played { TodayPulse(color: lab.patch(0)) }
                            if isToday { Circle().inset(by: 1).stroke(lab.patch(0), lineWidth: 2) }
                            if played { Icon(Icons.Rounded.LocalFireDepartment, tint: .white, size: 15) }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Rectangle().fill(lab.glassStroke).frame(height: 1)
            HStack(spacing: 0) {
                ZStack {
                    ProgressRing(value, 6, lab.surfaceAlt, LinearGradient(colors: [lab.paletteBrand, lab.paletteBrandEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(pct == 0 ? "0%" : (pct < 10 ? String(format: "%.1f%%", pct) : "\(Int(pct))%"))
                        .font(rounded(11, .heavy)).foregroundStyle(lab.ink)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Overall").font(rounded(15, .heavy)).foregroundStyle(lab.ink)
                    Text("\(total.grouped) levels").font(rounded(12, .semibold)).foregroundStyle(lab.ink2)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                MiniStat(value: store.totalSolved, label: "Solved", icon: Icons.Rounded.Verified, color: lab.ok)
                Spacer().frame(width: 18)
                MiniStat(value: store.totalStars, label: "Stars", icon: Icons.Rounded.Star, color: lab.sun)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .labGlass(Lab.Radius.bigCard)
    }
}

/// Today's ring pulse (1.4 s, restarting); Android runs it regardless of Reduce Motion.
private struct TodayPulse: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { tl in
            let p = fastOutSlowIn(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4)
            Canvas { ctx, s in
                _ = p
                let r = min(s.width, s.height) / 2 / 1.4 * (1 + 0.4 * p)
                let c = CGPoint(x: s.width / 2, y: s.height / 2)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color.copy(alpha: 0.7 * (1 - p))), lineWidth: 2)
            }
            .frame(width: 34 * 1.4, height: 34 * 1.4)
        }
        .allowsHitTesting(false)
    }
}

private struct MiniStat: View {
    let value: Int
    let label: String
    let icon: ImageVector
    let color: Color

    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Icon(icon, tint: color, size: 13)
                Text(value.grouped).font(rounded(17, .heavy)).foregroundStyle(lab.ink)
            }
            Text(label).font(rounded(11, .bold)).foregroundStyle(lab.ink2)
        }
        .fixedSize()
    }
}
