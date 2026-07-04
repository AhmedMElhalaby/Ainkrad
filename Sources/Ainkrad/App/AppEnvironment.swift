import Foundation

/// The composition root, assembled once in `AinkradApp.init` and injected
/// via `.environment(_:)`. See State, Persistence & Dependency Injection.md.
@MainActor
@Observable
final class AppEnvironment {
    let persistence: PersistenceStore
    let secrets: SecretStore
    let registry: BuiltInAppRegistry
    let themeManager: ThemeManager
    let workspaceManager: WorkspaceManager
    let launcherStore: LauncherStore
    let terminalSettingsStore: TerminalSettingsStore
    let connectionStore: ConnectionStore
    var isLauncherPresented = false
    var isWorkspaceOverviewPresented = false
    var isSettingsPresented = false

    init(
        persistence: PersistenceStore,
        secrets: SecretStore,
        registry: BuiltInAppRegistry,
        themeManager: ThemeManager,
        workspaceManager: WorkspaceManager,
        launcherStore: LauncherStore,
        terminalSettingsStore: TerminalSettingsStore,
        connectionStore: ConnectionStore
    ) {
        self.persistence = persistence
        self.secrets = secrets
        self.registry = registry
        self.themeManager = themeManager
        self.workspaceManager = workspaceManager
        self.launcherStore = launcherStore
        self.terminalSettingsStore = terminalSettingsStore
        self.connectionStore = connectionStore
    }

    /// Assembles a real `AppEnvironment` backed by the file document store and
    /// the Keychain. `rootURL` defaults to Application Support; tests pass a
    /// temp directory. `defaults` is the legacy import source (`.standard`).
    static func bootstrap(rootURL: URL? = nil, defaults: UserDefaults = .standard) -> AppEnvironment {
        let persistence = FileDocumentStore(rootURL: rootURL ?? FileDocumentStore.defaultDocumentsURL())
        let secrets = KeychainSecretStore()

        // One-time import of M1's UserDefaults settings before any store reads.
        LegacyUserDefaultsMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let registry = BuiltInAppRegistry(persistence: persistence)
        let themeManager = ThemeManager(
            persistence: persistence,
            dockIconUpdater: AppKitDockIconUpdater()
        )
        themeManager.applyResolvedIcon()

        let workspaceManager = WorkspaceManager()

        let environment = AppEnvironment(
            persistence: persistence,
            secrets: secrets,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: LauncherStore(registry: registry, workspaceManager: workspaceManager),
            terminalSettingsStore: TerminalSettingsStore(persistence: persistence),
            connectionStore: ConnectionStore(persistence: persistence, secrets: secrets)
        )

        // Built-in apps' chrome fill captures the environment, so install after it exists.
        registry.install(builtIn: [RegisteredApp.builtIn(TerminalApp.self, environment: environment)])

        if let saved = persistence.load(LayoutStateSnapshot.self) {
            workspaceManager.restore(from: saved)
            workspaceManager.pruneApps(keeping: Set(registry.allApps.map { $0.id }))
            Log.app.info("Restored workspace layout: \(saved.workspaces.count) workspace(s)")
        }
        workspaceManager.onStateChange = { [weak workspaceManager] in
            guard let workspaceManager else { return }
            persistence.save(workspaceManager.snapshot())
        }

        Log.app.info("AppEnvironment bootstrapped with \(registry.allApps.count) registered app(s)")
        return environment
    }
}
