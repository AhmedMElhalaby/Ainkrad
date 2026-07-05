import Observation

/// Holds the active theme, exposes theme tokens, and is the single place the
/// theme is applied: update state and persist. See ADR-0006 Theming Approach.
@MainActor
@Observable
final class ThemeManager {
    private(set) var currentTheme: Theme
    private let persistence: PersistenceStore

    var tokens: DesignTokens { currentTheme.tokens }

    /// Fired after a theme change is applied + persisted. Used by the app-icon
    /// store to re-apply the Dock icon when the color is Auto. Mirrors
    /// `WorkspaceManager.onStateChange`.
    var onThemeChange: (() -> Void)?

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        self.currentTheme = settings.theme
    }

    func setTheme(_ theme: Theme) {
        currentTheme = theme
        persist()
        onThemeChange?()
        Log.settings.info("Theme changed to \(theme.rawValue, privacy: .public)")
    }

    private func persist() {
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.theme = currentTheme
        persistence.save(settings)
    }
}
