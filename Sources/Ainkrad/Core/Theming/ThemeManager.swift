import Observation

/// Holds the active theme, exposes its tokens, and is the single place a
/// theme change is applied: update state, persist, swap the Dock icon.
/// See ADR-0006 Theming Approach and ADR-0008.
@MainActor
@Observable
final class ThemeManager {
    private static let settingsKey = "global-settings"

    private(set) var currentTheme: Theme
    private let settingsStore: SettingsStore
    private let dockIconUpdater: DockIconUpdating

    var tokens: DesignTokens { currentTheme.tokens }

    init(settingsStore: SettingsStore, dockIconUpdater: DockIconUpdating) {
        self.settingsStore = settingsStore
        self.dockIconUpdater = dockIconUpdater
        let settings = settingsStore.get(GlobalSettings.self, forKey: Self.settingsKey) ?? GlobalSettings()
        self.currentTheme = settings.theme
    }

    func setTheme(_ theme: Theme) {
        currentTheme = theme

        var settings = settingsStore.get(GlobalSettings.self, forKey: Self.settingsKey) ?? GlobalSettings()
        settings.theme = theme
        settingsStore.set(settings, forKey: Self.settingsKey)

        dockIconUpdater.updateDockIcon(for: theme)
        Log.settings.info("Theme changed to \(theme.rawValue, privacy: .public)")
    }
}
