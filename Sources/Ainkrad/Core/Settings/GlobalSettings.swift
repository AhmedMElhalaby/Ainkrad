/// App-wide settings persisted through `SettingsStore`. `theme` defaults to
/// `.neonBlue` and `appIcon` to `.auto` on first launch (see ADR-0006 Theming
/// Approach and `AppIconChoice`). Decoding tolerates payloads written before
/// `appIcon` existed — a missing field falls back to `.auto`.
struct GlobalSettings: PersistableDocument {
    static let documentID = "global-settings"
    var theme: Theme = .neonBlue
    var appIcon: AppIconChoice = .auto

    init(theme: Theme = .neonBlue, appIcon: AppIconChoice = .auto) {
        self.theme = theme
        self.appIcon = appIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .neonBlue
        appIcon = try container.decodeIfPresent(AppIconChoice.self, forKey: .appIcon) ?? .auto
    }
}
