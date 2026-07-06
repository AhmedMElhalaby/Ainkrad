import Observation

/// Owns the Settings → General section. Currently just the full-screen
/// status bar toggle (AIN-109); will also host the sound toggle in a later
/// issue. Loads from `GlobalSettings` and persists changes while preserving
/// the rest of the document — same load/mutate/save pattern as
/// `AppIconStore`.
@MainActor
@Observable
final class GeneralSettingsStore {
    private(set) var showFullScreenStatusBar: Bool
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        self.showFullScreenStatusBar = settings.showFullScreenStatusBar
    }

    func setShowFullScreenStatusBar(_ isOn: Bool) {
        showFullScreenStatusBar = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.showFullScreenStatusBar = isOn
        persistence.save(settings)
    }
}
