import Observation

/// Observable owner of `TerminalSettings`, injected via `AppEnvironment`.
/// Editing here persists immediately AND publishes to observers, so the
/// Settings UI and every running Terminal restyle live (see
/// `TerminalContainerView`). Session-resolution reads (shell / working
/// directory) still come from `SettingsStore` at session creation.
@MainActor
@Observable
final class TerminalSettingsStore {
    private(set) var settings: TerminalSettings
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        self.settings = store.get(TerminalSettings.self, forKey: TerminalSettings.storeKey) ?? TerminalSettings()
    }

    /// Mutates the settings, publishes to observers, and persists immediately.
    func update(_ mutate: (inout TerminalSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        settings = updated
        store.set(updated, forKey: TerminalSettings.storeKey)
    }
}
