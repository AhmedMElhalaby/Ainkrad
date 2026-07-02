/// App-wide settings persisted through `SettingsStore`. `theme` defaults to
/// `.neonBlue` on first launch, per ADR-0006 Theming Approach.
struct GlobalSettings: Codable, Equatable {
    var theme: Theme = .neonBlue
}
