/// App-wide settings persisted through `SettingsStore`. `theme` defaults to
/// `.neonBlue` on first launch (see ADR-0006 Theming Approach). Decoding
/// tolerates payloads written before/after fields changed — a missing `theme`
/// falls back to the default.
struct GlobalSettings: PersistableDocument {
    static let documentID = "global-settings"
    var theme: Theme = .neonBlue

    init(theme: Theme = .neonBlue) {
        self.theme = theme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .neonBlue
    }
}
