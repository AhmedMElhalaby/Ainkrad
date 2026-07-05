import Foundation

/// The composition root, assembled once in `AinkradHostApp.init` and injected
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
    let connectionStore: ConnectionStore
    let marketplace: MarketplaceService
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
        connectionStore: ConnectionStore,
        marketplace: MarketplaceService
    ) {
        self.persistence = persistence
        self.secrets = secrets
        self.registry = registry
        self.themeManager = themeManager
        self.workspaceManager = workspaceManager
        self.launcherStore = launcherStore
        self.connectionStore = connectionStore
        self.marketplace = marketplace
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

        // Plugin loading/marketplace plumbing needs to exist before
        // `AppEnvironment` is constructed, since `marketplace` is one of its
        // stored dependencies.
        let documentsRoot = rootURL ?? FileDocumentStore.defaultDocumentsURL()
        let pluginDirs = [
            documentsRoot.appendingPathComponent("Plugins", isDirectory: true),
            documentsRoot.appendingPathComponent("DevPlugins", isDirectory: true),
        ]
        let pluginDataRoot = documentsRoot.appendingPathComponent("PluginData", isDirectory: true)
        let loader = PluginLoader(signaturePolicy: DevModeSignaturePolicy()) { appID in
            HostServicesImpl(appID: appID, dataRootURL: pluginDataRoot,
                             secretStore: secrets, themeManager: themeManager)
        }

        let firstPartyRepos = ["AhmedMElhalaby/AinkradTerminal"]   // bundled first-party repo list (grows as apps ship)
        let catalogService = CatalogService(
            source: GitHubReleasesCatalogSource(repositories: firstPartyRepos, http: URLSessionHTTPClient()),
            persistence: persistence)
        let installer = PluginInstaller(
            http: URLSessionHTTPClient(), unzipper: DittoUnzipper(),
            pluginsDir: documentsRoot.appendingPathComponent("Plugins", isDirectory: true),
            pluginDataDir: pluginDataRoot,
            persistence: persistence, registry: registry,
            loadBundle: { loader.loadBundle(at: $0) })
        let marketplace = MarketplaceService(catalog: catalogService, installer: installer, persistence: persistence)

        let environment = AppEnvironment(
            persistence: persistence,
            secrets: secrets,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: LauncherStore(registry: registry, workspaceManager: workspaceManager),
            connectionStore: ConnectionStore(persistence: persistence, secrets: secrets),
            marketplace: marketplace
        )

        // Terminal is compiled-in but runs on the SDK surface: give it its own
        // scoped HostServices, migrate any pre-decouple host-global settings once,
        // then register it through the single built-in adapter.
        let terminalHost = HostServicesImpl(appID: TerminalApp.id, dataRootURL: pluginDataRoot,
                                            secretStore: secrets, themeManager: themeManager)
        TerminalSettingsMigration.runIfNeeded(legacy: persistence, scoped: terminalHost.documents, defaults: defaults)

        let loaded = loader.loadAll(from: pluginDirs)
        registry.install(
            builtIn: [RegisteredApp.builtIn(TerminalApp.self, host: terminalHost)],
            loaded: loaded.apps,
            failures: loaded.failures
        )

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
