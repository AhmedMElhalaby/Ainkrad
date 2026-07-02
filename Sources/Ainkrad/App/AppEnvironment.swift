import Foundation

/// The composition root, assembled once in `AinkradApp.init` and injected
/// via `.environment(_:)`. See State, Persistence & Dependency Injection.md.
@MainActor
@Observable
final class AppEnvironment {
    let settingsStore: SettingsStore
    let registry: BuiltInAppRegistry
    let themeManager: ThemeManager
    let workspaceManager: WorkspaceManager
    let launcherStore: LauncherStore
    var isLauncherPresented = false

    init(
        settingsStore: SettingsStore,
        registry: BuiltInAppRegistry,
        themeManager: ThemeManager,
        workspaceManager: WorkspaceManager,
        launcherStore: LauncherStore
    ) {
        self.settingsStore = settingsStore
        self.registry = registry
        self.themeManager = themeManager
        self.workspaceManager = workspaceManager
        self.launcherStore = launcherStore
    }

    /// Assembles a real `AppEnvironment` backed by `UserDefaults` and
    /// `NSApplication`. `defaults` defaults to `.standard`; tests pass an
    /// isolated suite.
    static func bootstrap(defaults: UserDefaults = .standard) -> AppEnvironment {
        let settingsStore = UserDefaultsSettingsStore(defaults: defaults)
        let registry = BuiltInAppRegistry(apps: [TerminalApp.self, SettingsApp.self], settingsStore: settingsStore)
        let themeManager = ThemeManager(
            settingsStore: settingsStore,
            dockIconUpdater: AppKitDockIconUpdater()
        )
        let workspaceManager = WorkspaceManager()
        Log.app.info("AppEnvironment bootstrapped with \(registry.allApps.count) registered Built-in Apps")
        return AppEnvironment(
            settingsStore: settingsStore,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: LauncherStore(registry: registry, workspaceManager: workspaceManager)
        )
    }
}
