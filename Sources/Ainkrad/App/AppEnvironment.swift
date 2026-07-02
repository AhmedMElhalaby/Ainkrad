import Foundation

/// The composition root, assembled once in `AinkradApp.init` and injected
/// via `.environment(_:)`. See State, Persistence & Dependency Injection.md.
@MainActor
final class AppEnvironment {
    let settingsStore: SettingsStore
    let registry: BuiltInAppRegistry
    let themeManager: ThemeManager
    let workspaceManager: WorkspaceManager

    init(
        settingsStore: SettingsStore,
        registry: BuiltInAppRegistry,
        themeManager: ThemeManager,
        workspaceManager: WorkspaceManager
    ) {
        self.settingsStore = settingsStore
        self.registry = registry
        self.themeManager = themeManager
        self.workspaceManager = workspaceManager
    }

    /// Assembles a real `AppEnvironment` backed by `UserDefaults` and
    /// `NSApplication`. `defaults` defaults to `.standard`; tests pass an
    /// isolated suite. The Built-in App list is empty until the Terminal
    /// and Settings Features are implemented.
    static func bootstrap(defaults: UserDefaults = .standard) -> AppEnvironment {
        let settingsStore = UserDefaultsSettingsStore(defaults: defaults)
        let registry = BuiltInAppRegistry(apps: [], settingsStore: settingsStore)
        let themeManager = ThemeManager(
            settingsStore: settingsStore,
            dockIconUpdater: AppKitDockIconUpdater()
        )
        return AppEnvironment(
            settingsStore: settingsStore,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: WorkspaceManager()
        )
    }
}
