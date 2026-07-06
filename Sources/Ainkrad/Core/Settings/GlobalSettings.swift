/// App-wide settings persisted through `SettingsStore`. `theme` defaults to
/// `.neonBlue` on first launch (see ADR-0006 Theming Approach). Decoding
/// tolerates payloads written before/after fields changed — a missing `theme`
/// falls back to the default.
struct GlobalSettings: PersistableDocument {
    static let documentID = "global-settings"
    var theme: Theme = .neonBlue
    var appIconChoice: AppIconChoice = .auto
    var appIconAppearance: AppIconAppearance = .system
    var confirmBeforeQuit: Bool = true

    init(theme: Theme = .neonBlue,
         appIconChoice: AppIconChoice = .auto,
         appIconAppearance: AppIconAppearance = .system,
         confirmBeforeQuit: Bool = true) {
        self.theme = theme
        self.appIconChoice = appIconChoice
        self.appIconAppearance = appIconAppearance
        self.confirmBeforeQuit = confirmBeforeQuit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .neonBlue
        appIconChoice = try container.decodeIfPresent(AppIconChoice.self, forKey: .appIconChoice) ?? .auto
        appIconAppearance = try container.decodeIfPresent(AppIconAppearance.self, forKey: .appIconAppearance) ?? .system
        confirmBeforeQuit = try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeQuit) ?? true
    }
}
