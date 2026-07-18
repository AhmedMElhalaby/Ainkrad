import Testing
import Foundation
@testable import Ainkrad

private struct NoOpCatalogSource: CatalogSource {
    func fetchCatalog() async throws -> [CatalogEntry] { [] }
}

@Suite("AppEnvironment")
final class AppEnvironmentTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ainkrad-tests-\(UUID().uuidString)")
    deinit { try? FileManager.default.removeItem(at: root) }

    @Test("exposes the exact dependencies it was constructed with")
    @MainActor
    func exposesInjectedDependencies() {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let registry = BuiltInAppRegistry(persistence: persistence)
        let themeManager = ThemeManager(persistence: persistence)
        let workspaceManager = WorkspaceManager()
        let appAppearanceStore = AppAppearanceStore(persistence: persistence)
        let launcherStore = LauncherStore(registry: registry, workspaceManager: workspaceManager, appAppearanceStore: appAppearanceStore)
        let connectionStore = ConnectionStore(persistence: persistence, secrets: secrets)
        let catalogService = CatalogService(
            source: NoOpCatalogSource(), persistence: persistence)
        let installer = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: FileManager.default.temporaryDirectory.appendingPathComponent("plugins"),
            pluginDataDir: FileManager.default.temporaryDirectory.appendingPathComponent("plugin-data"),
            retainedDataDir: FileManager.default.temporaryDirectory.appendingPathComponent("retained-plugin-data"),
            persistence: persistence, registry: registry, loadBundle: { _ in .failure(PluginRejection(reason: "x")) })
        let appStore = AppStoreService(catalog: catalogService, installer: installer, persistence: persistence)
        let appStoreStore = AppStoreStore(service: appStore, registry: registry)
        let shortcutStore = ShortcutStore(persistence: persistence)
        let quitCoordinator = QuitCoordinator(persistence: persistence, terminator: FakeTerminationReplier())
        let generalSettingsStore = GeneralSettingsStore(persistence: persistence)
        let sounds = SoundEngine(settings: generalSettingsStore)
        let agentContextHub = AgentContextRegistryHub()
        let agentActionHub = AgentActionRegistryHub()
        let agentConfigStore = AgentConfigStore(persistence: persistence)
        let agentContextSettingsStore = AgentContextSettingsStore(persistence: persistence)
        let agentContextService = AgentContextService(hub: agentContextHub, settings: agentContextSettingsStore)
        let agentPermissionStore = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() })
        let agentStore = AgentStore(persistence: persistence)
        let agentSession = AgentSession(
            providerFor: { (connection: Connection) -> LLMProvider in
                switch connection.kind {
                case .claude: return ClaudeProvider(http: URLSessionStreamingHTTPClient())
                case .openAICompatible: return OpenAICompatibleProvider(http: URLSessionStreamingHTTPClient(), baseURL: connection.baseURL)
                case .gemini: return GeminiProvider(http: URLSessionStreamingHTTPClient(), baseURL: connection.baseURL)
                }
            },
            connections: connectionStore,
            config: agentConfigStore,
            context: agentContextService,
            registry: AgentToolRegistry(tools: [ReadFileTool(), EditFileTool()]),
            permissions: agentPermissionStore,
            agents: agentStore
        )

        let environment = AppEnvironment(
            persistence: persistence,
            secrets: secrets,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: launcherStore,
            connectionStore: connectionStore,
            appStore: appStore,
            appStoreStore: appStoreStore,
            appIconStore: AppIconStore(persistence: persistence, applier: AppKitAppIconApplier(), themeManager: themeManager),
            shortcutStore: shortcutStore,
            quitCoordinator: quitCoordinator,
            generalSettingsStore: generalSettingsStore,
            appAppearanceStore: appAppearanceStore,
            skySettingsStore: SkySettingsStore(persistence: persistence),
            sounds: sounds,
            agentContextHub: agentContextHub,
            agentActionHub: agentActionHub,
            agentConfigStore: agentConfigStore,
            agentPermissionStore: agentPermissionStore,
            agentContextSettingsStore: agentContextSettingsStore,
            agentContextService: agentContextService,
            agentStore: agentStore,
            agentSession: agentSession,
            modelCatalogService: ModelCatalogService(http: URLSessionDataHTTPClient()),
            modelCatalog: ModelCatalog(),
            modelPriceTable: ModelPriceTable(),
            usageTracker: UsageTracker(persistence: persistence, prices: ModelPriceTable()),
            routerOutcomeStore: RouterOutcomeStore(persistence: persistence),
            modelRouter: ModelRouter(catalog: ModelCatalog(), outcomes: RouterOutcomeStore(persistence: persistence)),
            runtimeOptionsStore: RuntimeOptionsStore(persistence: persistence),
            localModelProbe: LocalModelProbe(catalog: ModelCatalogService(http: URLSessionDataHTTPClient())),
            authProfileStore: AuthProfileStore(persistence: persistence, secrets: secrets),
            commandRegistry: CommandRegistry(builtins: []),
            memoryService: nil
        )

        #expect(environment.registry === registry)
        #expect(environment.agentStore === agentStore)
        #expect(environment.agentPermissionStore === agentPermissionStore)
        #expect(environment.agentPermissionStore.mode == .ask)
        #expect(environment.themeManager === themeManager)
        #expect(environment.workspaceManager === workspaceManager)
        #expect(environment.launcherStore === launcherStore)
        #expect(environment.connectionStore === connectionStore)
        #expect(environment.appStore === appStore)
        #expect(environment.appStoreStore === appStoreStore)
        #expect(environment.shortcutStore === shortcutStore)
        #expect(environment.quitCoordinator === quitCoordinator)
        #expect(environment.generalSettingsStore === generalSettingsStore)
        #expect(environment.isFullScreen == false)
    }

    @Test("bootstrap() assembles a working environment on isolated storage, Launcher dismissed")
    @MainActor
    func bootstrapAssemblesRealDependencies() {
        // Isolate the legacy-import source too: bootstrap runs
        // LegacyUserDefaultsMigration against `defaults`, so a shared
        // `.standard` would import stray real `com.ainkrad.app` state and
        // make these assertions non-hermetic on any machine/CI runner.
        let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment.bootstrap(rootURL: root, defaults: isolatedDefaults)
        #expect(environment.themeManager.currentTheme == .neonBlue)
        // Terminal is an App Store plugin, not built-in; Assistant is the one
        // compiled-in built-in the host registers itself (M5 Phase B).
        #expect(environment.registry.allApps.map(\.id) == ["assistant"])
        #expect(environment.workspaceManager.workspaces.count == 1)
        #expect(environment.isLauncherPresented == false)
        #expect(environment.isSettingsPresented == false)
        #expect(environment.quitCoordinator.isConfirming == false)
        #expect(environment.isFullScreen == false)
        #expect(environment.generalSettingsStore.showFullScreenStatusBar == true)
        // Regression guard for the test-isolation leak: the memory subsystem
        // must be constructed under the injected `root`, never the real
        // `~/Library/Application Support/<bundle-id>/Memory` — otherwise every
        // `make test` run reindexes the developer's real memory store.
        #expect(environment.memoryService != nil)
        let isolatedMemoryIndex = root.appendingPathComponent("Memory", isDirectory: true)
            .appendingPathComponent("index.sqlite")
        #expect(FileManager.default.fileExists(atPath: isolatedMemoryIndex.path))
    }
}
