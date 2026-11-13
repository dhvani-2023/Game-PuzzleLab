import SwiftUI
import UIKit
import GameKit

/// One scene, all SwiftUI: splash → onboarding (first launch only) → the app shell (Android `MainActivity`).
@main
struct PuzzleLabApp: App {
    @UIApplicationDelegateAdaptor(GameAppDelegate.self) private var appDelegate

    init() {
        FontRegistry.registerAll()
        let state = AppState.shared
        Haptics.setup(state.settings)
        SoundEngine.setup(state.settings)
        OrientationLock.shared.mask = .portrait
        LabTheme.shared.refreshSystem()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppState.shared)
        }
    }
}

private struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    var body: some View {
        let state = AppState.shared
        let settings = state.settings
        let dark = LabTheme.shared.dark
        let stage = showSplash ? 0 : (!settings.hasCompletedOnboarding ? 1 : 2)
        ZStack {
            LabBackground(animated: false)
            ZStack {
                switch stage {
                case 0:
                    SplashScreen { showSplash = false }
                case 1:
                    OnboardingScreen { startID in
                        state.router.replaceAll(startID.map { [Route.Levels($0)] } ?? [])
                        settings.setOnboardingDone(true)
                    }
                default:
                    MainShell()
                }
            }
            .id(stage)
            .transition(.opacity)
            LabPromptHost()
        }
        .animation(tween(450), value: stage)
        .preferredColorScheme(dark ? .dark : .light)
        .statusBarHidden(false)
        // Full-screen like a game: the home indicator fades away (Android hides its navigation bar).
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                AppLifecycle.resumed = true
                AudioSystem.shared.resume()
                LabTheme.shared.refreshSystem()
            case .inactive, .background:
                if AppLifecycle.resumed {
                    AppLifecycle.resumed = false
                    AppLifecycle.pauses += 1
                }
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)) { _ in
            LabTheme.shared.refreshSystem()
        }
        .onChange(of: settings.motion) { _, _ in LabTheme.shared.refreshSystem() }
    }
}
