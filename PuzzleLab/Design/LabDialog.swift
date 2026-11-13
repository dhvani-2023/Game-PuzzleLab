import SwiftUI
import Observation

/// A confirmation or offer, shown by `LabPromptHost` over everything (replaces system dialogs).
final class LabPrompt: Identifiable {
    enum Role { case Normal, Primary, Destructive, Cancel }

    final class Choice {
        let title: String
        let role: Role
        let icon: ImageVector?
        let action: () -> Void

        init(_ title: String, _ role: Role = .Normal, _ icon: ImageVector? = nil, action: @escaping () -> Void = {}) {
            self.title = title
            self.role = role
            self.icon = icon
            self.action = action
        }

        convenience init(title: String, role: Role = .Normal, icon: ImageVector? = nil, action: @escaping () -> Void = {}) {
            self.init(title, role, icon, action: action)
        }
    }

    let id = UUID()
    let icon: ImageVector
    let tint: Color?
    let title: String
    let message: String?
    let choices: [Choice]

    init(_ icon: ImageVector, _ tint: Color? = nil, _ title: String, _ message: String? = nil, choices: [Choice]) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.message = message
        self.choices = choices
    }

    convenience init(icon: ImageVector, tint: Color? = nil, title: String, message: String? = nil, choices: [Choice]) {
        self.init(icon, tint, title, message, choices: choices)
    }
}

@Observable
final class PromptCenterState {
    var prompt: LabPrompt?
}

/// Holds the prompt on screen; any screen can set it.
enum PromptCenter {
    static let state = PromptCenterState()

    static var prompt: LabPrompt? {
        get { state.prompt }
        set { state.prompt = newValue }
    }

    static func show(_ prompt: LabPrompt) {
        UISound.tap()
        state.prompt = prompt
    }
}

/// Sits over the whole app (root ZStack) and shows `PromptCenter.prompt`.
struct LabPromptHost: View {
    var body: some View {
        let prompt = PromptCenter.state.prompt
        ZStack {
            if prompt != nil {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2)), removal: .opacity.animation(.easeIn(duration: 0.18))))
            }
            if let prompt {
                LabConfirmCard(prompt: prompt) { choice in
                    PromptCenter.prompt = nil
                    choice.action()
                }
                .id(prompt.id)
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.16)).combined(with: .scale(scale: 0.86).animation(labSpring(0.42, 0.72))),
                    removal: .opacity.combined(with: .scale(scale: 0.94)).animation(tween(140))
                ))
            }
        }
        .animation(labSpring(0.42, 0.72), value: prompt?.id)
    }
}

private struct LabConfirmCard: View {
    let prompt: LabPrompt
    let onChoose: (LabPrompt.Choice) -> Void
    @State private var bounce: CGFloat = 1

    var body: some View {
        let lab = Lab.colors
        let tint = prompt.tint ?? lab.danger
        let offer = prompt.choices.contains { $0.role == .Primary }
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.copy(alpha: 0.18)).frame(width: 74, height: 74)
                Icon(prompt.icon, tint: .white, size: 26)
                    .scaleEffect(bounce)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(LinearGradient(colors: [tint.mix(.white, 0.2), tint.mix(.black, 0.15)], startPoint: .top, endPoint: .bottom)))
                    .labShadow(tint.copy(alpha: 0.45), 10, 5, circle: true)
            }
            .frame(width: 74, height: 74)
            Text(prompt.title).font(gameTextStyle(22)).foregroundStyle(lab.ink).multilineTextAlignment(.center)
            if let message = prompt.message {
                Text(message).font(rounded(15, .semibold)).foregroundStyle(lab.ink2).multilineTextAlignment(.center)
            }
            VStack(spacing: 8) {
                ForEach(Array(prompt.choices.enumerated()), id: \.offset) { _, choice in
                    switch choice.role {
                    case .Primary:
                        LabPrimaryButton(choice.title, icon: choice.icon, height: 52) { onChoose(choice) }
                    case .Destructive:
                        LabPrimaryButton(choice.title, icon: choice.icon, colors: GameColors.red, height: 52) { onChoose(choice) }
                    case .Cancel:
                        if offer {
                            LabSecondaryButton(choice.title, fill: true) { onChoose(choice) }
                        } else {
                            LabPrimaryButton(choice.title, height: 52) { onChoose(choice) }
                        }
                    case .Normal:
                        LabSecondaryButton(choice.title, fill: true, icon: choice.icon) { onChoose(choice) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .gamePopup(30, [tint.mix(.white, 0.2), tint])
        .padding(.horizontal, 28)
        .task {
            Haptics.warning()
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(tween(120)) { bounce = 1.18 }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(labSpring(0.42, 0.5)) { bounce = 1 }
        }
    }
}
