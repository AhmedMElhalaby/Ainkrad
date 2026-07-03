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
    var isWorkspaceOverviewPresented = false
    var isSettingsPresented = false

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
        // Settings is a summonable overlay, not a tiled Block, so it is not a
        // registered app — Terminal is the only Built-in App in the registry.
        let registry = BuiltInAppRegistry(apps: [TerminalApp.self], settingsStore: settingsStore)
        let themeManager = ThemeManager(
            settingsStore: settingsStore,
            dockIconUpdater: AppKitDockIconUpdater()
        )
        // Apply the persisted Dock-icon preference once at launch.
        themeManager.applyResolvedIcon()
        let workspaceManager = WorkspaceManager()
        // Restore the persisted workspace/pane layout, then wire autosave:
        // any structural change re-snapshots to the store.
        if let saved = settingsStore.get(LayoutStateSnapshot.self, forKey: LayoutStateSnapshot.storeKey) {
            workspaceManager.restore(from: saved)
            // Drop panes for apps that no longer exist as tiled Blocks (e.g. a
            // Settings pane persisted before Settings became an overlay).
            workspaceManager.pruneApps(keeping: Set(registry.allApps.map { $0.id }))
            Log.app.info("Restored workspace layout: \(saved.workspaces.count) workspace(s)")
        }
        workspaceManager.onStateChange = { [weak workspaceManager] in
            guard let workspaceManager else { return }
            settingsStore.set(workspaceManager.snapshot(), forKey: LayoutStateSnapshot.storeKey)
        }
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
