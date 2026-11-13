import Foundation
import Observation

/// Who's playing: a name and an avatar, set in onboarding or Settings.
@Observable
final class PlayerProfile {
    private(set) var name = ""
    private(set) var avatar = PlayerProfile.AVATARS[0]
    private(set) var colorIndex = 0

    @ObservationIgnored private static let key = "player.profile.v1"

    static let AVATARS = ["🦊", "🐼", "🐯", "🐸", "🦄", "🐙", "🐧", "🦁", "🐨", "🐵", "🐰", "🐲", "🦉", "🐝", "🐬", "🦖"]
    /// Patch palette indices of the six token colours: Coral, Sky, Mint, Sun, Lavender, Rose.
    static let TOKEN_PATCHES = [0, 5, 3, 2, 6, 7]

    init() {
        if let raw = Prefs.string(Self.key), let o = JSONObject(string: raw) {
            name = o.optString("name")
            avatar = o.optString("avatar", Self.AVATARS[0])
            colorIndex = o.optInt("colorIndex")
        }
    }

    func updateName(_ value: String) { name = String(value.prefix(24)); save() }
    func updateAvatar(_ value: String, _ color: Int) { avatar = value; colorIndex = color; save() }

    /// The trimmed name, or "Player" when it was left blank.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "Player" : trimmed).prefix(18))
    }

    private func save() {
        let o = JSONObject().putting("name", name).putting("avatar", avatar).putting("colorIndex", colorIndex)
        Prefs.putString(Self.key, o.toString())
    }
}
