import SwiftUI
import Observation

/// Foreground state of the app, so clocks pause and boards save when the app leaves.
@Observable
final class AppLifecycleModel {
    var resumed = true
    /// Bumped every time the app leaves the foreground.
    var pauses = 0
}

enum AppLifecycle {
    static let model = AppLifecycleModel()

    static var resumed: Bool {
        get { model.resumed }
        set { model.resumed = newValue }
    }

    static var pauses: Int {
        get { model.pauses }
        set { model.pauses = newValue }
    }
}

/// Live state of one Patches or Zip level, as the shared play shell sees it. Implement as an
/// `@Observable final class` so the shell redraws when it changes.
protocol PuzzleSession: AnyObject, Observable {
    var levelID: Int { get }
    var elapsed: Int { get set }
    var hintsUsed: Int { get }
    var isSolved: Bool { get }
    var canUndo: Bool { get }
    var canClear: Bool { get }
    /// 0…1 completion for the progress bar.
    var progress: Float { get }
    var progressText: String { get }
    var statusText: String { get }
    var feedbackMessage: String? { get }
    /// Bumped on rejected moves (error haptic, toast).
    var errorCount: Int { get }
    /// Bumped on accepted moves (impact haptic).
    var actionCount: Int { get }
    /// Bumped on every board change (autosave).
    var revision: Int { get }

    func undo()
    func clear()
    func hint()
    func clearFeedback()
    /// Encoded in-progress state, or nil when there is nothing worth restoring.
    func encodeState() -> String?
}

private final class SessionBox<S> {
    var value: S?
}

/// The play screen shared by Patches and Zip: header, timer, progress, tools, error toast, autosave,
/// how-to-play and the level-complete flow. Games only provide the board.
struct GameShell<S: PuzzleSession, Board: View>: View {
    let module: any GameModule
    let startLevel: Int
    let makeSession: (Int, String?) -> S
    @ViewBuilder let board: (S) -> Board

    init(module: any GameModule, startLevel: Int, makeSession: @escaping (Int, String?) -> S, @ViewBuilder board: @escaping (S) -> Board) {
        self.module = module
        self.startLevel = startLevel
        self.makeSession = makeSession
        self.board = board
    }

    @Environment(AppState.self) private var app
    @State private var box = SessionBox<S>()
    @State private var generation = 0
    @State private var showComplete = false
    @State private var isNewBest = false
    @State private var showHowTo = false

    private var gameID: String { module.info.id }
    private var progress: GameProgress { app.store.progress(gameID) }

    private var session: S {
        if let s = box.value { return s }
        let s = makeSession(startLevel, progress.savedState(startLevel, module.catalog.version))
        box.value = s
        return s
    }

    private func save() {
        guard let s = box.value else { return }
        if !s.isSolved { progress.saveState(s.encodeState(), s.levelID, module.catalog.version) }
    }

    private func load(_ level: Int) {
        save()
        showComplete = false
        isNewBest = false
        box.value = makeSession(level, progress.savedState(level, module.catalog.version))
        withAnimation(labSpring(0.5, 0.8)) { generation += 1 }
    }

    var body: some View {
        let lab = Lab.colors
        let s = session
        let catalog = module.catalog
        ZStack {
            LabBackground()
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    GameBackButton { app.router.pop() }
                    VStack(spacing: 4) {
                        // One line: 4-digit levels shrink to fit beside the timer.
                        Text("Level \(s.levelID)")
                            .font(rounded(22, .heavy))
                            .foregroundStyle(lab.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(14.0 / 22.0)
                        if let tier = catalog.tier(s.levelID) {
                            TierChip(tier.title, tierIcon(tier), tierColor(tier, lab))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    GameCounter(Icons.Rounded.Schedule, formatTime(s.elapsed), GameColors.blue, height: 38)
                    CircleIconButton(Icons.Rounded.QuestionMark) { showHowTo = true }
                }
                .padding(.horizontal, 20)
                Spacer().frame(height: 16)
                // Progress
                VStack(spacing: 6) {
                    if s.isSolved {
                        CapsuleBar(Double(s.progress), LinearGradient(colors: [lab.ok, lab.ok], startPoint: .leading, endPoint: .trailing), lab.surfaceAlt)
                    } else {
                        CapsuleBar(Double(s.progress), module.info.gradient, lab.surfaceAlt)
                    }
                    HStack(spacing: 0) {
                        Text(s.statusText).font(rounded(12, .semibold)).foregroundStyle(lab.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(s.progressText).font(rounded(12, .semibold)).foregroundStyle(lab.inkSecondary)
                    }
                }
                .padding(.horizontal, 24)
                // Board
                ZStack {
                    board(s)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(generation)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(tween(250)).combined(with: .scale(scale: 0.85)),
                            removal: .opacity.animation(tween(200)).combined(with: .scale(scale: 1.05))
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Tools
                HStack(spacing: 12) {
                    GameToolKey("Undo", Icons.AutoMirrored.Rounded.Undo, GameColors.slate(), enabled: s.canUndo) {
                        PuzzleSound.play(.Remove)
                        s.undo()
                    }
                    GameToolKey("Clear", Icons.Rounded.AutoFixNormal, GameColors.slate(), enabled: s.canClear) {
                        PuzzleSound.play(.Clear)
                        s.clear()
                    }
                    GameToolKey("Hint", Icons.Rounded.Lightbulb, GameColors.gold, enabled: !s.isSolved, badge: s.hintsUsed > 0 ? "\(s.hintsUsed)" : nil) {
                        PuzzleSound.play(.Hint)
                        Haptics.impactLight()
                        s.hint()
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)

            ErrorToast(message: s.feedbackMessage)

            if showComplete {
                LevelCompleteView(
                    module: module,
                    levelID: s.levelID,
                    time: s.elapsed,
                    bestTime: progress.record(s.levelID)?.bestTime,
                    isNewBest: isNewBest,
                    stars: Scoring.stars(s.hintsUsed),
                    hintsUsed: s.hintsUsed,
                    isLastLevel: s.levelID >= catalog.count,
                    onNext: {
                        let next = s.levelID + 1
                        if next <= catalog.count { load(next) } else { app.router.backToLevels(gameID) }
                    },
                    onReplay: {
                        progress.saveState(nil, s.levelID, catalog.version)
                        load(s.levelID)
                    },
                    onLevels: { app.router.backToLevels(gameID) }
                )
                .transition(.asymmetric(insertion: .opacity.animation(tween(300)), removal: .opacity.animation(tween(200))))
                .zIndex(2)
            }
            if showHowTo {
                HowToPlaySheet(module) { showHowTo = false }
                    .zIndex(3)
            }
        }
        .onAppear {
            app.store.markPlayed(gameID)
        }
        .task {
            let key = "howToPlay.\(gameID).seen"
            if !Prefs.bool(key) {
                Prefs.putBool(key, true)
                try? await Task.sleep(nanoseconds: 450_000_000)
                showHowTo = true
            }
        }
        // The clock: one tick a second while the app is in front and the board is unsolved.
        .task(id: generation) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                let cur = session
                if AppLifecycle.resumed && !cur.isSolved && !showHowTo { cur.elapsed += 1 }
            }
        }
        .onChange(of: s.revision) { save() }
        .onChange(of: AppLifecycle.pauses) { save() }
        .onDisappear { save() }
        .onChange(of: s.actionCount) { _, n in if n > 0 { Haptics.impactMedium() } }
        .onChange(of: s.errorCount) { _, n in
            if n > 0 {
                Haptics.error()
                PuzzleSound.play(.Error)
            }
        }
        .task(id: "\(generation)-\(s.isSolved)") {
            let cur = session
            guard cur.isSolved else { return }
            isNewBest = app.store.recordSolve(gameID, cur.levelID, cur.elapsed, cur.hintsUsed)
            Haptics.success()
            PuzzleSound.play(.Solved)
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            if Task.isCancelled { return }
            withAnimation(tween(300)) { showComplete = true }
        }
        .task(id: "\(generation)-\(s.errorCount)") {
            guard session.feedbackMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if Task.isCancelled { return }
            withAnimation(tween(220)) { session.clearFeedback() }
        }
    }
}

/// The red pill that drops in under the header when a move is rejected.
private struct ErrorToast: View {
    let message: String?

    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 0) {
            if let message {
                HStack(spacing: 8) {
                    Icon(Icons.Rounded.Error, tint: .white, size: 18)
                    Text(message).font(rounded(14, .bold)).foregroundStyle(Color.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(LinearGradient(colors: [lab.danger.copy(alpha: 0.95), lab.danger], startPoint: .top, endPoint: .bottom))
                .clipShape(Capsule())
                .labShadow(lab.danger.copy(alpha: 0.35), 12, 6, 24)
                .padding(.top, 64)
                .transition(.asymmetric(
                    insertion: .offset(y: -140).combined(with: .opacity),
                    removal: .offset(y: -140).combined(with: .opacity)
                ))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(labSpring(0.4, 0.75), value: message)
        .allowsHitTesting(false)
    }
}

/// Glass tool button (the iOS play shell's older tool style).
struct ToolButton: View {
    let title: String
    let icon: ImageVector
    let enabled: Bool
    let badge: Int?
    let highlighted: Bool
    let onClick: () -> Void

    init(_ title: String, _ icon: ImageVector, enabled: Bool, badge: Int?, highlighted: Bool, onClick: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.enabled = enabled
        self.badge = badge
        self.highlighted = highlighted
        self.onClick = onClick
    }

    var body: some View {
        let lab = Lab.colors
        let color = highlighted ? lab.sun : lab.ink
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Icon(icon, tint: color, size: 22)
                Text(title).font(rounded(13, .bold)).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(RoundedRectangle(cornerRadius: 22, style: .circular).fill(lab.surface))
            .labShadow(Color.black.opacity(0.05), 10, 4, 22)
            .opacity(enabled ? 1 : 0.45)
            .animation(tween(200), value: enabled)
            .pressable(0.95, enabled: enabled, onClick: onClick)
            if let badge {
                Text("\(badge)").font(rounded(11, .heavy)).foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(lab.sun))
                    .offset(x: -8, y: 6)
            }
        }
    }
}
