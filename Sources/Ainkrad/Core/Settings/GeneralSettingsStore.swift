import Observation

/// Owns the Settings → General section: the full-screen status bar toggle
/// (AIN-109) and the sound effects toggle/volume (AIN-108). Loads from
/// `GlobalSettings` and persists changes while preserving the rest of the
/// document — same load/mutate/save pattern as `AppIconStore`.
///
/// Conforms to `SoundSettingsProviding` so `SoundEngine` can read
/// enabled/volume directly off this store — no separate settings object.
@MainActor
@Observable
final class GeneralSettingsStore: SoundSettingsProviding {
    private(set) var showFullScreenStatusBar: Bool
    private(set) var soundEnabled: Bool
    private(set) var soundVolume: Double
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        self.showFullScreenStatusBar = settings.showFullScreenStatusBar
        self.soundEnabled = settings.soundEnabled
        self.soundVolume = settings.soundVolume
    }

    func setShowFullScreenStatusBar(_ isOn: Bool) {
        showFullScreenStatusBar = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.showFullScreenStatusBar = isOn
        persistence.save(settings)
    }

    func setSoundEnabled(_ isOn: Bool) {
        soundEnabled = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.soundEnabled = isOn
        persistence.save(settings)
    }

    func setSoundVolume(_ volume: Double) {
        soundVolume = volume
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.soundVolume = volume
        persistence.save(settings)
    }
}
