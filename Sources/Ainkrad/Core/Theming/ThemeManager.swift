import Observation

/// Holds the active theme and the Dock-icon preference, exposes theme tokens,
/// and is the single place either is applied: update state, persist, swap the
/// Dock icon. The icon is decoupled from the theme (see `AppIconChoice`): an
/// explicit choice survives theme changes; `.auto` follows the theme.
/// See ADR-0006 Theming Approach and ADR-0008.
@MainActor
@Observable
final class ThemeManager {
    private static let settingsKey = "global-settings"

    private(set) var currentTheme: Theme
    private(set) var appIcon: AppIconChoice
    private let settingsStore: SettingsStore
    private let dockIconUpdater: DockIconUpdating

    var tokens: DesignTokens { currentTheme.tokens }

    init(settingsStore: SettingsStore, dockIconUpdater: DockIconUpdating) {
        self.settingsStore = settingsStore
        self.dockIconUpdater = dockIconUpdater
        let settings = settingsStore.get(GlobalSettings.self, forKey: Self.settingsKey) ?? GlobalSettings()
        self.currentTheme = settings.theme
        self.appIcon = settings.appIcon
    }

    /// Applies the currently-resolved Dock icon. Call once at bootstrap so a
    /// persisted preference (explicit or theme-derived) takes effect at launch
    /// — it isn't applied in `init` to keep construction side-effect-free.
    func applyResolvedIcon() {
        dockIconUpdater.updateDockIcon(appIcon.resolvedIcon(for: currentTheme))
    }

    func setTheme(_ theme: Theme) {
        currentTheme = theme
        persist()

        // Only follow the theme when the icon is on Auto; an explicit icon
        // choice must not be overridden by a theme change.
        if appIcon == .auto {
            dockIconUpdater.updateDockIcon(appIcon.resolvedIcon(for: theme))
        }
        Log.settings.info("Theme changed to \(theme.rawValue, privacy: .public)")
    }

    func setAppIcon(_ choice: AppIconChoice) {
        appIcon = choice
        persist()
        dockIconUpdater.updateDockIcon(choice.resolvedIcon(for: currentTheme))
        Log.settings.info("App icon set to \(choice.rawValue, privacy: .public)")
    }

    private func persist() {
        var settings = settingsStore.get(GlobalSettings.self, forKey: Self.settingsKey) ?? GlobalSettings()
        settings.theme = currentTheme
        settings.appIcon = appIcon
        settingsStore.set(settings, forKey: Self.settingsKey)
    }
}
