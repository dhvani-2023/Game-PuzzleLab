import SwiftUI

/// A legal document shown in the app, rendered from the text below (offline; the Android build's live
/// web page carries the same text).
final class LegalDoc {
    let id: String
    let title: String
    let icon: ImageVector
    let colors: [Color]
    let intro: String
    let sections: [(String, [String])]

    init(id: String, title: String, icon: ImageVector, colors: [Color], intro: String, sections: [(String, [String])]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.colors = colors
        self.intro = intro
        self.sections = sections
    }

    static let UPDATED = "8 November 2026"
    static let EMAIL = "ngendevtech@gmail.com"
    private static let contact = "NG Studio (NGENDEV TECHNOLABS LLP)\nEmail: \(EMAIL)\nPhone: +91 90237 85087\n1213, R K Prime, 12th Floor, Near Nana Mava Circle, 150 Feet Ring Road, Rajkot, Gujarat 360005, India"

    static let privacy = LegalDoc(
        id: "privacy",
        title: "Privacy Policy",
        icon: Icons.Rounded.PrivacyTip,
        colors: [hex(0x2FB9A0), hex(0x3D8BFF)],
        intro: "Puzzle Lab (\"the app\") is an offline puzzle game published by NG Studio (NGENDEV TECHNOLABS LLP). This policy explains what information the app handles. "
            + "In short: the app does not collect, share or sell any personal information.",
        sections: [
            ("Information we collect", [
                "We do not collect any personal information. The app has no accounts and no sign-in, and it contains no analytics, tracking or advertising software.",
                "The app does not connect to the internet, so it cannot send any information off your device.",
            ]),
            ("Information stored on your device", [
                "To let you continue where you left off, the app saves the following only in its private storage on your device:",
                "• Game progress: levels solved, stars, best times and boards in progress.\n• Coins earned while playing.\n• Settings: sound, haptics, theme and motion.\n• The optional name and avatar you choose.",
                "This information never leaves your device through the app, and we cannot see or access it.",
            ]),
            ("Device backup", [
                "If backup is turned on in your device settings, iOS may include the app's saved data in your device backup (for example, an iCloud backup). "
                    + "This is controlled by your device settings and Apple's policies. We cannot access these backups.",
            ]),
            ("Advertising", [
                "This version of the app does not show advertisements and contains no advertising software.",
            ]),
            ("Permissions", [
                "Haptics: used for feedback while you play. You can turn haptics off at any time in Settings.",
                "The app requests no other permissions. It does not use your location, camera, microphone, contacts, photos or files.",
            ]),
            ("Children's privacy", [
                "The app is suitable for all ages. Because it collects no personal information from anyone, it collects none from children.",
            ]),
            ("Sharing with third parties", [
                "The app does not share any information with third parties.",
            ]),
            ("Deleting your data", [
                "You can erase all your data at any time with Settings › Reset everything, or by deleting the app.",
            ]),
            ("Changes to this policy", [
                "If a future version changes how information is handled (for example, by adding advertising), this policy will be updated before that version is released, and the date at the top will change.",
            ]),
            ("Contact", [
                "If you have any questions about this privacy policy, please contact us:",
                contact,
            ]),
        ]
    )

    static let terms = LegalDoc(
        id: "terms",
        title: "Terms & Conditions",
        icon: Icons.Rounded.Gavel,
        colors: [hex(0x6E5BFF), hex(0xB45CFF)],
        intro: "By downloading or using Puzzle Lab (\"the app\"), published by NG Studio (NGENDEV TECHNOLABS LLP), you agree to these terms. If you do not agree, please do not use the app.",
        sections: [
            ("Using the app", [
                "You may use the app for your own personal, non-commercial enjoyment. This permission is non-exclusive and non-transferable, and it may be withdrawn if these terms are broken.",
            ]),
            ("Ownership", [
                "The app and everything in it, including its games, levels, artwork, sounds, code and names, belongs to the developer and is protected by intellectual property laws.",
                "You may not copy, modify, distribute, sell, rent or reverse engineer the app, except where the law expressly allows it.",
            ]),
            ("Coins and rewards", [
                "Coins, stars, hints and other rewards are virtual items for use inside the app only. They have no monetary value and cannot be bought, sold, exchanged or redeemed for money or anything else.",
                "Because your progress is stored only on your device, it may be lost if you reset the app or delete it.",
            ]),
            ("Advertisements", [
                "The app does not display third-party advertisements or require ad viewing to play.",
            ]),
            ("Fair play", [
                "Please do not use cheats, modified versions of the app or other tools to change how the app works, and do not use the app for any unlawful purpose.",
            ]),
            ("Updates and availability", [
                "The app is provided free of charge. We may update it, change or remove features, or stop offering it at any time.",
            ]),
            ("Play safely", [
                "Take regular breaks. Do not play while driving or in any situation that needs your full attention. "
                    + "If animations or flashing effects make you uncomfortable, stop playing; you can calm them with Settings › Reduce motion.",
            ]),
            ("Disclaimer", [
                "To the extent permitted by law, the app is provided \"as is\" and \"as available\", without warranties of any kind, whether express or implied.",
            ]),
            ("Limitation of liability", [
                "To the extent permitted by law, the developer is not liable for any indirect or consequential loss, or for any loss of game progress or data, arising from your use of the app.",
                "Nothing in these terms limits any liability that cannot be limited by law, or affects your statutory rights as a consumer.",
            ]),
            ("App store terms", [
                "Your use of the app is also subject to the terms of the store you downloaded it from, such as the App Store.",
            ]),
            ("Changes to these terms", [
                "We may update these terms from time to time. The date at the top shows the latest version. If you keep using the app after a change, you accept the updated terms.",
            ]),
            ("Contact", [
                "If you have any questions about these terms, please contact us:",
                contact,
            ]),
        ]
    )

    static func of(_ id: String) -> LegalDoc { id == terms.id ? terms : privacy }
}

/// A legal page: the document's sections on glass, with the contact e-mail as a mail link.
struct LegalScreen: View {
    let doc: LegalDoc

    init(_ doc: LegalDoc) { self.doc = doc }

    @Environment(AppState.self) private var app

    var body: some View {
        let lab = Lab.colors
        ZStack {
            LabBackground(animated: false)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    GameBackButton { app.router.pop() }
                    Text(doc.title).font(LabText.headline).foregroundStyle(lab.ink).multilineTextAlignment(.center)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                    Spacer().frame(width: 46)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Icon(doc.icon, tint: .white, size: 26)
                                .frame(width: 52, height: 52)
                                .background(RoundedRectangle(cornerRadius: 16, style: .circular).fill(LinearGradient(colors: doc.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
                                .labShadow((doc.colors.first ?? .clear).copy(alpha: 0.45), 12, 6, 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Puzzle Lab").font(LabText.cardTitle).foregroundStyle(lab.ink)
                                Text("Last updated: \(LegalDoc.UPDATED)").font(LabText.caption).foregroundStyle(lab.ink2)
                            }
                        }
                        Text(doc.intro).font(rounded(15, .semibold)).foregroundStyle(lab.ink).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(doc.sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.0).font(rounded(17, .heavy)).foregroundStyle(lab.ink)
                                ForEach(Array(section.1.enumerated()), id: \.offset) { _, paragraph in
                                    Text(linked(paragraph))
                                        .font(rounded(14, .semibold))
                                        .foregroundStyle(lab.ink2)
                                        .tint(lab.paletteBrand)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .labGlass(Lab.Radius.card)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    /// The contact e-mail as a tappable mail link.
    private func linked(_ text: String) -> AttributedString {
        var s = AttributedString(text)
        if let r = s.range(of: LegalDoc.EMAIL) {
            s[r].link = URL(string: "mailto:\(LegalDoc.EMAIL)")
            s[r].underlineStyle = .single
        }
        return s
    }
}
