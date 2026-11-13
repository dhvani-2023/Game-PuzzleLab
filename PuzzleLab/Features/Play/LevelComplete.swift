import SwiftUI

func formatTime(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

struct ExtraStat {
    let label: String
    let value: String
    let icon: ImageVector

    init(label: String, value: String, icon: ImageVector) {
        self.label = label
        self.value = value
        self.icon = icon
    }

    init(_ label: String, _ value: String, _ icon: ImageVector) {
        self.init(label: label, value: value, icon: icon)
    }
}

/// The win card: rays, confetti, stars popping in one by one, stats and the next step.
struct LevelCompleteView: View {
    let module: any GameModule
    let levelID: Int
    let time: Int
    let bestTime: Int?
    let isNewBest: Bool
    let stars: Int
    let hintsUsed: Int
    let isLastLevel: Bool
    let onNext: () -> Void
    let onReplay: () -> Void
    let onLevels: () -> Void
    var extraStat: ExtraStat? = nil
    var subtitle: String? = nil

    init(module: any GameModule, levelID: Int, time: Int, bestTime: Int?, isNewBest: Bool, stars: Int, hintsUsed: Int, isLastLevel: Bool,
         onNext: @escaping () -> Void, onReplay: @escaping () -> Void, onLevels: @escaping () -> Void,
         extraStat: ExtraStat? = nil, subtitle: String? = nil) {
        self.module = module
        self.levelID = levelID
        self.time = time
        self.bestTime = bestTime
        self.isNewBest = isNewBest
        self.stars = stars
        self.hintsUsed = hintsUsed
        self.isLastLevel = isLastLevel
        self.onNext = onNext
        self.onReplay = onReplay
        self.onLevels = onLevels
        self.extraStat = extraStat
        self.subtitle = subtitle
    }

    @State private var appear = false
    @State private var iconIn = false
    @State private var shownStars = 0

    var body: some View {
        let lab = Lab.colors
        let info = module.info
        let a: Double = appear ? 1 : 0
        let title: String = {
            if isLastLevel { return "Legendary!" }
            if stars >= 3 { return "Flawless!" }
            if stars == 2 { return "Great job!" }
            return "Solved!"
        }()
        ZStack {
            Color.black.opacity(0.4 * a)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            ConfettiView()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    RotatingRays(lab.sun).frame(width: 210, height: 210)
                    module.BadgeArt(64)
                        .frame(width: 64, height: 64)
                        .scaleEffect(iconIn ? 1 : 0.3)
                        .rotationEffect(.degrees(iconIn ? 0 : -40))
                        .frame(width: 112, height: 112)
                        .background(Circle().fill(info.gradient))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 3))
                        .labShadow(info.first.copy(alpha: 0.5), 20, 10, circle: true)
                }
                .frame(width: 210, height: 140)
                .offset(y: 70)
                .zIndex(1)
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text(title).font(gameTextStyle(36, Color.black.opacity(0.3))).foregroundStyle(lab.ink)
                        Text(subtitle ?? (isLastLevel ? "You've conquered all \(levelID) levels" : "Level \(levelID) complete"))
                            .font(rounded(16, .semibold)).foregroundStyle(lab.inkSecondary).multilineTextAlignment(.center)
                    }
                    HStack(alignment: .center, spacing: 14) {
                        ForEach(0..<3, id: \.self) { i in
                            let on = i < shownStars
                            let side: CGFloat = i == 1 ? 52 : 44
                            Icon(Icons.Rounded.Star, tint: on ? lab.sun : lab.surfaceAlt, size: side)
                                .scaleEffect(on ? 1 : 0.7)
                                .rotationEffect(.degrees(on ? 0 : -30))
                                .labShadow(on ? lab.sun.copy(alpha: 0.5) : .clear, 10, 4, circle: true)
                                .animation(labSpring(0.42, 0.5), value: on)
                                .offset(y: i == 1 ? -8 : 0)
                        }
                    }
                    HStack(spacing: 0) {
                        StatCell(label: "Time", value: formatTime(time), icon: Icons.Rounded.Schedule, highlight: false)
                        Rectangle().fill(lab.gridLine).frame(width: 1, height: 34)
                        StatCell(label: isNewBest ? "New best!" : "Best", value: formatTime(bestTime ?? time), icon: Icons.Rounded.EmojiEvents, highlight: isNewBest)
                        Rectangle().fill(lab.gridLine).frame(width: 1, height: 34)
                        if let extraStat {
                            StatCell(label: extraStat.label, value: extraStat.value, icon: extraStat.icon, highlight: false)
                        } else {
                            StatCell(label: "Hints", value: "\(hintsUsed)", icon: Icons.Rounded.Lightbulb, highlight: false)
                        }
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 20, style: .circular).fill(lab.surfaceAlt.copy(alpha: 0.6)))
                    VStack(spacing: 12) {
                        if !isLastLevel {
                            LabPrimaryButton("Next Level", trailingIcon: Icons.AutoMirrored.Rounded.ArrowForward, colors: info.colors, height: 58) {
                                Haptics.cta()
                                onNext()
                            }
                        }
                        HStack(spacing: 12) {
                            SurfaceButton(title: "Replay", icon: Icons.Rounded.Replay, onClick: onReplay)
                            SurfaceButton(title: "Levels", icon: Icons.Rounded.GridView, onClick: onLevels)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 80)
                .frame(maxWidth: .infinity)
                .gamePopup(36, info.colors)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 22)
            .opacity(a)
            .scaleEffect(0.8 + 0.2 * a)
            .offset(y: (1 - a) * 300)
        }
        .onAppear {
            PuzzleSound.play(.Win)
            withAnimation(labSpring(0.55, 0.78)) { appear = true }
            withAnimation(labSpring(0.5, 0.5).delay(0.08)) { iconIn = true }
        }
        .task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            for _ in 0..<stars {
                if Task.isCancelled { return }
                shownStars += 1
                PuzzleSound.play(.Star, 0)
                Haptics.impactLight()
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
        }
    }
}

private struct StatCell: View {
    let label: String
    let value: String
    let icon: ImageVector
    let highlight: Bool

    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Icon(icon, tint: highlight ? lab.sun : lab.inkSecondary, size: 12)
                Text(label).font(rounded(12, .bold)).foregroundStyle(highlight ? lab.sun : lab.inkSecondary).lineLimit(1)
            }
            Text(value).font(rounded(20, .heavy)).foregroundStyle(lab.ink).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SurfaceButton: View {
    let title: String
    let icon: ImageVector
    let onClick: () -> Void

    var body: some View {
        GameButton(title, fill: true, icon: icon, colors: GameColors.slate(), height: 52, fontSize: 16, onClick: onClick)
            .frame(maxWidth: .infinity)
    }
}

/// Step-by-step rules sheet, shown the first time a game opens and from the "?" button.
struct HowToPlaySheet: View {
    let module: any GameModule
    let onDone: () -> Void

    init(_ module: any GameModule, onDone: @escaping () -> Void) {
        self.module = module
        self.onDone = onDone
    }

    init(module: any GameModule, onDone: @escaping () -> Void) {
        self.init(module, onDone: onDone)
    }

    @State private var appear = false
    @State private var stepsIn = false

    var body: some View {
        let lab = Lab.colors
        let info = module.info
        let t: Double = appear ? 1 : 0
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45 * t)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDone() }
            VStack(spacing: 0) {
                Capsule().fill(lab.gridLine).frame(width: 40, height: 5)
                VStack(spacing: 10) {
                    module.BadgeArt(50)
                        .frame(width: 50, height: 50)
                        .frame(width: 64, height: 64)
                        .background(RoundedRectangle(cornerRadius: 20, style: .circular).fill(info.gradient))
                        .labShadow(info.first.copy(alpha: 0.4), 12, 6, 20)
                    Text("HOW TO PLAY").font(rounded(13, .heavy)).tracking(1.5).foregroundStyle(lab.paletteBrand)
                    Text(info.name).font(rounded(30, .heavy)).foregroundStyle(lab.ink)
                }
                .padding(.top, 22)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(module.howToPlay.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Icon(step.icon, tint: info.first, size: 20)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(info.first.copy(alpha: 0.14)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title).font(rounded(16, .heavy)).foregroundStyle(lab.ink)
                                Text(step.message).font(rounded(14, .medium)).foregroundStyle(lab.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .opacity(stepsIn ? 1 : 0)
                        .offset(x: stepsIn ? 0 : 24)
                        .animation(tween(450).delay(0.1 + Double(index) * 0.08), value: stepsIn)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                LabPrimaryButton("Got it", colors: info.colors, height: 58) { onDone() }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .circular)
                    .fill(lab.background)
                    .ignoresSafeArea(edges: .bottom)
            )
            .contentShape(Rectangle())
            .onTapGesture {}
            .visualEffect { content, proxy in
                content.offset(y: (1 - t) * (proxy.size.height + 40))
            }
        }
        .onAppear {
            withAnimation(labSpring(0.5, 0.86)) { appear = true }
            stepsIn = true
        }
    }
}
