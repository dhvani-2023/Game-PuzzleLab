import SwiftUI

/// Settings: profile, feel, look, your data and about. Shown as a tab and full-screen.
struct SettingsScreen: View {
    let bottomInset: CGFloat
    var embedded: Bool = true

    init(_ bottomInset: CGFloat, embedded: Bool = true) {
        self.bottomInset = bottomInset
        self.embedded = embedded
    }

    @Environment(AppState.self) private var app
    @State private var driver = ScrollDriver()

    var body: some View {
        let lab = Lab.colors
        DrivenScrollView(driver: driver, onOffset: { app.settingsScroll = $0 }) {
            VStack(spacing: 24) {
                ZStack {
                    Text("Settings").font(gameTextStyle(26)).foregroundStyle(lab.ink)
                    if !embedded {
                        HStack {
                            GameBackButton { app.router.pop() }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                Appear(0) { ProfileCard() }
                Appear(1) { Feel(settings: app.settings) }
                Appear(2) { Look(settings: app.settings) }
                Appear(3) { DataSection() }
                Appear(4) { LegalSection() }
                Appear(5) { About() }
                Footer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, bottomInset + 32)
        }
        .onAppear {
            // Settings keeps its place when a legal page opens over it and closes again.
            if app.settingsScroll > 0 { driver.scrollTo(y: app.settingsScroll) }
        }
    }
}

private func ribbonColors(_ title: String) -> [Color] {
    switch title {
    case "Feel": return GameColors.pink
    case "Look": return GameColors.blue
    case "Your data": return GameColors.teal
    case "Legal": return GameColors.gold
    default: return GameColors.purple
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        let lab = Lab.colors
        VStack(alignment: .leading, spacing: 8) {
            GameRibbon(title, ribbonColors(title)).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity)
                .labGlass()
            if let footer {
                Text(footer).font(LabText.caption).foregroundStyle(lab.ink2).padding(.horizontal, 8)
            }
        }
    }
}

private struct ProfileCard: View {
    @Environment(AppState.self) private var app
    @State private var editing = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let lab = Lab.colors
        let store = app.store
        let profile = app.profile
        let xp = store.labXP
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                LabLevelAvatar(72)
                    .overlay(alignment: .bottomLeading) {
                        Icon(Icons.Rounded.Edit, tint: .white, size: 11)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(lab.brand))
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                            .offset(x: -2, y: 2)
                    }
                    .pressable(0.94, sound: true) { withAnimation(tween(300)) { editing.toggle() } }
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .leading) {
                        if profile.name.isEmpty {
                            Text("Your name").font(rounded(20, .black)).foregroundStyle(lab.ink2.copy(alpha: 0.6)).allowsHitTesting(false)
                        }
                        TextField("", text: Binding(get: { profile.name }, set: { profile.updateName($0) }))
                            .font(rounded(20, .black))
                            .foregroundStyle(lab.ink)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit { nameFocused = false }
                            .tint(lab.brand)
                    }
                    Text("Lab level \(LabLevel.level(xp)) · \(xp.grouped) XP").font(LabText.caption).foregroundStyle(lab.ink2)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(lab.glassStroke)
                            Capsule().fill(LinearGradient(colors: [lab.sun, hex(0xFF8A3D)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, g.size.width * CGFloat(LabLevel.progress(xp))))
                        }
                    }
                    .frame(height: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if editing {
                AvatarPicker(profile: profile)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: 8) {
                StatPill(Icons.Rounded.LocalFireDepartment, "\(store.streak) days", lab.warn)
                StatPill(Icons.Rounded.Verified, store.totalSolved.grouped, lab.ok)
                StatPill(Icons.Rounded.Star, store.totalStars.grouped)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .labGlass(Lab.Radius.bigCard)
    }
}

/// A row of avatars; the chosen one sits large, in its colour.
struct AvatarPicker: View {
    let profile: PlayerProfile

    init(profile: PlayerProfile) { self.profile = profile }

    var body: some View {
        let lab = Lab.colors
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(PlayerProfile.AVATARS.enumerated()), id: \.offset) { index, avatar in
                    let selected = avatar == profile.avatar
                    let colorIndex = index % PlayerProfile.TOKEN_PATCHES.count
                    ProfileAvatar(avatar, lab.patch(PlayerProfile.TOKEN_PATCHES[colorIndex]), selected ? 86 : 56)
                        .animation(labSpring(0.42, 0.6), value: selected)
                        .pressable(0.9) {
                            UISound.tap()
                            Haptics.tap()
                            profile.updateAvatar(avatar, colorIndex)
                        }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 100)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity)
    }
}

private struct Feel: View {
    let settings: AppSettings

    var body: some View {
        SettingsGroup(title: "Feel") {
            SettingsRow(Icons.Rounded.VolumeUp, hex(0xFF5C93), "Sound effects") {
                LabToggle(settings.soundEnabled) { settings.updateSound($0) }
            }
            GlassDivider()
            SettingsRow(Icons.Rounded.Vibration, hex(0x2FB9A0), "Haptics") {
                LabToggle(settings.hapticsEnabled) { on in
                    settings.updateHaptics(on)
                    if on { Haptics.toggle() }
                }
            }
            GlassDivider()
            SettingsRow(Icons.Rounded.DirectionsRun, hex(0x3D8BFF), "Reduce motion", subtitle: "Calmer screens and transitions")
            GlassSegmented(AppSettings.MotionPreference.allCases, { $0.title }, settings.motion) { settings.updateMotion($0) }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .onChange(of: settings.motion) { _, _ in LabTheme.shared.refreshSystem() }
        }
    }
}

private struct Look: View {
    let settings: AppSettings

    var body: some View {
        let lab = Lab.colors
        SettingsGroup(title: "Look") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme").font(LabText.label).foregroundStyle(lab.ink)
                HStack(spacing: 12) {
                    ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
                        ThemeSwatch(theme: theme, selected: settings.theme == theme) {
                            UISound.tap()
                            Haptics.tap()
                            settings.updateTheme(theme)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: AppSettings.Theme
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        let lab = Lab.colors
        let shape = RoundedRectangle(cornerRadius: Lab.Radius.small, style: .circular)
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                switch theme {
                case .Light: SwatchPreview(dark: false)
                case .Dark: SwatchPreview(dark: true)
                case .System:
                    SwatchPreview(dark: false)
                    SwatchPreview(dark: true)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? lab.brand : lab.glassStroke, lineWidth: selected ? 3 : 1))
            Text(theme.title).font(rounded(12, .heavy)).foregroundStyle(selected ? lab.ink : lab.ink2)
        }
        .frame(maxWidth: .infinity)
        .pressable(0.94, onClick: onClick)
    }
}

private struct SwatchPreview: View {
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: dark ? [hex(0x231C52), hex(0x14112E)] : [hex(0xF4F1FF), hex(0xFBF9F4)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let p: CGFloat = 8
            ctx.fill(Path(roundedRect: CGRect(x: p, y: p, width: 26, height: 5), cornerRadius: 2.5), with: .color(dark ? Color.white.opacity(0.85) : hex(0x1C1B29, 0.8)))
            ctx.fill(Path(roundedRect: CGRect(x: p, y: p + 9, width: 34, height: 14), cornerRadius: 4),
                     with: .linearGradient(Gradient(colors: [hex(0x6E5BFF), hex(0xB45CFF)]), startPoint: CGPoint(x: p, y: 0), endPoint: CGPoint(x: p + 34, y: 0)))
            for i in 0..<3 {
                ctx.fill(Path(roundedRect: CGRect(x: p + CGFloat(i) * 13, y: p + 27, width: 10, height: 10), cornerRadius: 3),
                         with: .color(dark ? Color.white.opacity(0.14) : Color.white))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DataSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        SettingsGroup(title: "Your data") {
            SettingsRow(Icons.Rounded.Security, lab.ok, "Your progress stays on this device", subtitle: "No accounts, no ads, works offline")
            GlassDivider()
            SettingsRow(Icons.Rounded.Replay, lab.warn, "Reset one game…", onClick: { pickGameToReset(app) })
            GlassDivider()
            SettingsRow(Icons.Rounded.DeleteForever, lab.danger, "Reset everything", titleColor: lab.danger, onClick: { confirmResetAll(app) })
        }
    }
}

private func pickGameToReset(_ app: AppState) {
    PromptCenter.show(
        LabPrompt(
            Icons.Rounded.Replay, hex(0xFF8A3D), "Reset which game?",
            choices: GameRegistry.games.map { m in LabPrompt.Choice(m.info.name) { confirmReset(app, m.info.id, m.info.name) } }
                + [LabPrompt.Choice("Cancel", .Cancel)]
        )
    )
}

private func confirmReset(_ app: AppState, _ id: String, _ name: String) {
    PromptCenter.show(
        LabPrompt(
            Icons.Rounded.Replay, hex(0xFF8A3D), "Reset \(name)?",
            "Solved levels, stars, saved boards and best scores for this game are removed. Coins are kept.",
            choices: [
                LabPrompt.Choice("Cancel", .Cancel),
                LabPrompt.Choice("Reset", .Destructive) {
                    app.store.resetGame(id)
                    app.settings.resetToken += 1
                    Haptics.warning()
                },
            ]
        )
    )
}

private func confirmResetAll(_ app: AppState) {
    PromptCenter.show(
        LabPrompt(
            Icons.Rounded.DeleteForever, nil, "Reset everything?",
            "Every game's progress and your streak will be removed from this device.",
            choices: [
                LabPrompt.Choice("Cancel", .Cancel),
                LabPrompt.Choice("Continue", .Destructive) {
                    PromptCenter.show(
                        LabPrompt(
                            Icons.Rounded.Warning, nil, "This can't be undone",
                            choices: [
                                LabPrompt.Choice("Keep my progress", .Cancel),
                                LabPrompt.Choice("Reset everything", .Destructive) {
                                    app.store.resetAll()
                                    app.settings.resetToken += 1
                                    Haptics.warning()
                                },
                            ]
                        )
                    )
                },
            ]
        )
    )
}

private struct LegalSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        SettingsGroup(title: "Legal") {
            SettingsRow(LegalDoc.privacy.icon, hex(0x2FB9A0), "Privacy Policy", onClick: {
                UISound.whoosh()
                app.router.push(.Legal(LegalDoc.privacy.id))
            }) {
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, tint: lab.ink2, size: 22)
            }
            GlassDivider()
            SettingsRow(LegalDoc.terms.icon, hex(0x6E5BFF), "Terms & Conditions", onClick: {
                UISound.whoosh()
                app.router.push(.Legal(LegalDoc.terms.id))
            }) {
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, tint: lab.ink2, size: 22)
            }
        }
    }
}

private struct About: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        SettingsGroup(title: "About") {
            SettingsRow(Icons.Rounded.Info, lab.brand, "Version") {
                Text(version).font(LabText.label).foregroundStyle(lab.ink2)
            }
            GlassDivider()
            SettingsRow(Icons.Rounded.AutoAwesome, hex(0x9B5CF6), "Replay intro", onClick: {
                app.router.replaceAll([])
                app.router.tab = .Home
                app.settings.setOnboardingDone(false)
            })
        }
    }
}

private struct Footer: View {
    var body: some View {
        let lab = Lab.colors
        VStack(spacing: 8) {
            PinwheelLogo(36)
            Text("Puzzle Lab").font(LabText.cardTitle).foregroundStyle(lab.ink)
            Text("Tiny puzzles. Big brain.").font(LabText.caption).foregroundStyle(lab.ink2)
            Spacer().frame(height: 8)
            // Separator
            GeometryReader { g in
                Rectangle().fill(lab.glassStroke).frame(width: g.size.width * 0.5, height: 1).frame(maxWidth: .infinity)
            }
            .frame(height: 1)
            Spacer().frame(height: 8)
            Text("POWERED BY").font(LabText.eyebrow).foregroundStyle(lab.ink2.copy(alpha: 0.5))
            Image("NGStudioLogo")
                .resizable()
                .aspectRatio(1.505, contentMode: .fit)
                .frame(width: 176)
                .accessibilityLabel("NG Studio")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}
