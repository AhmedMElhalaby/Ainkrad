import Foundation
import AinkradAppKit

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
    let appStore: AppStoreService
    let appStoreStore: AppStoreStore
    let appIconStore: AppIconStore
    let shortcutStore: ShortcutStore
    let quitCoordinator: QuitCoordinator
    let generalSettingsStore: GeneralSettingsStore
    let appAppearanceStore: AppAppearanceStore
    let skySettingsStore: SkySettingsStore
    let sounds: SoundPlaying
    let agentContextHub: AgentContextRegistryHub
    let agentActionHub: AgentActionRegistryHub
    let agentConfigStore: AgentConfigStore
    let agentPermissionStore: AgentPermissionStore
    let agentContextSettingsStore: AgentContextSettingsStore
    let agentContextService: AgentContextService
    let agentStore: AgentStore
    let agentSession: AgentSession
    /// M7 Slice 2 (MCP) — owns configured servers' live connections; its discovered
    /// tools feed `agentToolRegistry.dynamicTools` and its trust decisions feed
    /// `agentSession`'s `mcpTrust` closure. See `bootstrap()`.
    let mcpServerRegistry: MCPServerRegistry
    let modelCatalogService: ModelCatalogService
    /// M7 Slice 5b (Model Router / Usage / Failover) runtime wiring.
    let modelCatalog: ModelCatalog
    let modelPriceTable: ModelPriceTable
    let usageTracker: UsageTracker
    let routerOutcomeStore: RouterOutcomeStore
    let modelRouter: ModelRouter
    let runtimeOptionsStore: RuntimeOptionsStore
    let localModelProbe: LocalModelProbe
    /// Async-refreshed reachability cache gating LOCAL candidates in
    /// `candidatesProvider` (bootstrap) — see `LocalModelAvailability`.
    let localModelAvailability: LocalModelAvailability
    let authProfileStore: AuthProfileStore
    let commandRegistry: CommandRegistry
    /// The assistant memory subsystem (M7 Slice 1). `nil` when the FTS index
    /// couldn't be opened at launch — the app degrades to memory-less rather
    /// than crashing (see `bootstrap()`).
    let memoryService: MemoryService?
    var isLauncherPresented = false
    var isWorkspaceOverviewPresented = false
    var isSettingsPresented = false
    var isAppStorePresented = false
    var isQuickAskPresented = false
    #if DEBUG
    /// Component Gallery — DEBUG-only, reachable via the Launcher's system
    /// action row. Never compiled into release builds (AIN — Slice 1b Task 8).
    var isComponentGalleryPresented = false
    #endif
    /// The id of a `.overlay`-presentation plugin app currently summoned as a
    /// floating host overlay (Slice 3), or `nil` when none is shown. Cleared
    /// automatically when any app opens (see the launch-hub open handler in
    /// `bootstrap()`), so an overlay never lingers behind a newly-opened pane.
    var presentedOverlayAppID: String? = nil
    /// Tracks the host window's full-screen state — set by
    /// `KeyboardShortcutMonitor.MonitoringView` from `NSWindow`'s full-screen
    /// notifications (AIN-109). Drives `HUDBar`'s full-screen status bar;
    /// unused in windowed mode.
    var isFullScreen = false
    /// In full screen the top bar (traffic lights + status + workspace dots)
    /// stays hidden and reveals only while the pointer is at the top edge,
    /// Xcode-style — set by `MonitoringView`'s mouse-moved monitor. Ignored
    /// in windowed mode, where the bar is always shown.
    var isTopBarRevealed = false

    init(
        persistence: PersistenceStore,
        secrets: SecretStore,
        registry: BuiltInAppRegistry,
        themeManager: ThemeManager,
        workspaceManager: WorkspaceManager,
        launcherStore: LauncherStore,
        connectionStore: ConnectionStore,
        appStore: AppStoreService,
        appStoreStore: AppStoreStore,
        appIconStore: AppIconStore,
        shortcutStore: ShortcutStore,
        quitCoordinator: QuitCoordinator,
        generalSettingsStore: GeneralSettingsStore,
        appAppearanceStore: AppAppearanceStore,
        skySettingsStore: SkySettingsStore,
        sounds: SoundPlaying,
        agentContextHub: AgentContextRegistryHub,
        agentActionHub: AgentActionRegistryHub,
        agentConfigStore: AgentConfigStore,
        agentPermissionStore: AgentPermissionStore,
        agentContextSettingsStore: AgentContextSettingsStore,
        agentContextService: AgentContextService,
        agentStore: AgentStore,
        agentSession: AgentSession,
        mcpServerRegistry: MCPServerRegistry,
        modelCatalogService: ModelCatalogService,
        modelCatalog: ModelCatalog,
        modelPriceTable: ModelPriceTable,
        usageTracker: UsageTracker,
        routerOutcomeStore: RouterOutcomeStore,
        modelRouter: ModelRouter,
        runtimeOptionsStore: RuntimeOptionsStore,
        localModelProbe: LocalModelProbe,
        localModelAvailability: LocalModelAvailability,
        authProfileStore: AuthProfileStore,
        commandRegistry: CommandRegistry,
        memoryService: MemoryService?
    ) {
        self.persistence = persistence
        self.secrets = secrets
        self.registry = registry
        self.themeManager = themeManager
        self.workspaceManager = workspaceManager
        self.launcherStore = launcherStore
        self.connectionStore = connectionStore
        self.appStore = appStore
        self.appStoreStore = appStoreStore
        self.appIconStore = appIconStore
        self.shortcutStore = shortcutStore
        self.quitCoordinator = quitCoordinator
        self.generalSettingsStore = generalSettingsStore
        self.appAppearanceStore = appAppearanceStore
        self.skySettingsStore = skySettingsStore
        self.sounds = sounds
        self.agentContextHub = agentContextHub
        self.agentActionHub = agentActionHub
        self.agentConfigStore = agentConfigStore
        self.agentPermissionStore = agentPermissionStore
        self.agentContextSettingsStore = agentContextSettingsStore
        self.agentContextService = agentContextService
        self.agentStore = agentStore
        self.agentSession = agentSession
        self.mcpServerRegistry = mcpServerRegistry
        self.modelCatalogService = modelCatalogService
        self.modelCatalog = modelCatalog
        self.modelPriceTable = modelPriceTable
        self.usageTracker = usageTracker
        self.routerOutcomeStore = routerOutcomeStore
        self.modelRouter = modelRouter
        self.runtimeOptionsStore = runtimeOptionsStore
        self.localModelProbe = localModelProbe
        self.localModelAvailability = localModelAvailability
        self.authProfileStore = authProfileStore
        self.commandRegistry = commandRegistry
        self.memoryService = memoryService
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
        let themeManager = ThemeManager(persistence: persistence)

        let workspaceManager = WorkspaceManager()

        // Plugin loading/App Store plumbing needs to exist before
        // `AppEnvironment` is constructed, since `appStore` is one of its
        // stored dependencies.
        let documentsRoot = rootURL ?? FileDocumentStore.defaultDocumentsURL()
        let pluginDirs = [
            documentsRoot.appendingPathComponent("Plugins", isDirectory: true),
            documentsRoot.appendingPathComponent("DevPlugins", isDirectory: true),
        ]
        let pluginDataRoot = documentsRoot.appendingPathComponent("PluginData", isDirectory: true)
        let retainedDataRoot = documentsRoot.appendingPathComponent("RetainedPluginData", isDirectory: true)
        let agentContextHub = AgentContextRegistryHub()
        let agentActionHub = AgentActionRegistryHub()
        let pluginLaunchHub = PluginLaunchHub()
        let appAppearanceStore = AppAppearanceStore(persistence: persistence)
        let loader = PluginLoader(signaturePolicy: DevModeSignaturePolicy(), minSupportedAPIVersion: 4) { appID, declaredPresentation in
            HostServicesImpl(appID: appID, dataRootURL: pluginDataRoot,
                             secretStore: secrets, themeManager: themeManager,
                             hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                             declaredPresentation: declaredPresentation, appAppearanceStore: appAppearanceStore)
        }

        // The app catalog is a single hosted document (the central
        // AinkradCatalog). Adding/updating apps is a catalog edit — no host
        // release. Only this URL is compiled in.
        let catalogURL = URL(string: "https://raw.githubusercontent.com/AhmedMElhalaby/AinkradCatalog/main/catalog.json")!
        let catalogService = CatalogService(
            source: RemoteCatalogSource(url: catalogURL, http: URLSessionHTTPClient()),
            persistence: persistence)
        let installer = PluginInstaller(
            http: URLSessionHTTPClient(), unzipper: DittoUnzipper(),
            pluginsDir: documentsRoot.appendingPathComponent("Plugins", isDirectory: true),
            pluginDataDir: pluginDataRoot,
            retainedDataDir: retainedDataRoot,
            persistence: persistence, registry: registry,
            loadBundle: { loader.loadBundle(at: $0) })
        // Built here (rather than down by `mcpServerRegistry`, its other user)
        // so `AppStoreService` can be given the same store the MCP install
        // path (Task 13) records configs into — installing an MCP catalog
        // entry from the App Store must show up in the MCP manager and vice
        // versa.
        let mcpConfigStore = MCPServerConfigStore(persistence: persistence, secrets: secrets)
        let mcpInstaller = MCPServerInstaller(configStore: mcpConfigStore, persistence: persistence)
        let appStore = AppStoreService(catalog: catalogService, installer: installer,
                                        mcpInstaller: mcpInstaller, persistence: persistence)
        let appStoreStore = AppStoreStore(service: appStore, registry: registry)

        let appIconStore = AppIconStore(persistence: persistence,
                                        applier: AppKitAppIconApplier(),
                                        themeManager: themeManager)
        themeManager.onThemeChange = { [weak appIconStore] in appIconStore?.applyCurrent() }
        appIconStore.applyCurrent()

        let generalSettingsStore = GeneralSettingsStore(persistence: persistence)
        let skySettingsStore = SkySettingsStore(persistence: persistence)
        // User-data override dir for AIN-108's sound-pack overrides (e.g. via
        // scripts/install-sao-sounds.sh) — need not exist; SoundEngine falls
        // back to the bundled synth wavs when a given override is absent.
        let soundOverrideDirectory = documentsRoot.appendingPathComponent("Sounds", isDirectory: true)
        let sounds = SoundEngine(settings: generalSettingsStore, overrideDirectory: soundOverrideDirectory)
        // Plays exactly once per process, here rather than in a view's
        // `.onAppear` (which SwiftUI can re-fire) — `bootstrap()` itself only
        // ever runs once, from `AinkradHostApp.init`.
        sounds.play(.appLaunch)

        let connectionStore = ConnectionStore(persistence: persistence, secrets: secrets)

        // AgentKit services (M5 Phase B): one shared streaming HTTP client
        // backs both providers; `AgentSession` is the single read-only chat
        // loop the Assistant built-in (and, later, the ambient island) bind to.
        let streamingHTTP = URLSessionStreamingHTTPClient()
        let agentConfigStore = AgentConfigStore(persistence: persistence)
        let agentContextSettingsStore = AgentContextSettingsStore(persistence: persistence)
        let agentContextService = AgentContextService(hub: agentContextHub, settings: agentContextSettingsStore)
        let agentPermissionStore = AgentPermissionStore(
            persistence: persistence,
            currentWorkspaceID: { [weak workspaceManager] in
                workspaceManager?.activeWorkspaceID ?? UUID()
            })
        // Assistant memory (M7 Slice 1). Degrade-don't-crash: if the FTS index can't
        // open, the assistant runs memory-less this launch (mirrors FileDocumentStore's
        // corrupt-file quarantine posture) rather than taking the app down.
        // Mirrors `pluginDataRoot`/`retainedDataRoot` above: when a test injects
        // `rootURL`, the memory subdir is derived from that same isolated root
        // rather than the real Application Support path, so `make test` never
        // touches (or reindexes) the real on-disk memory store.
        let memoryRoot = rootURL != nil
            ? documentsRoot.appendingPathComponent("Memory", isDirectory: true)
            : MemoryPaths.defaultRoot()
        let memoryService = try? MemoryService(
            paths: MemoryPaths(root: memoryRoot),
            persistence: persistence)

        var agentTools: [any AgentTool] = [
            ReadFileTool(), EditFileTool(),
            WorkspaceControlTool(workspaces: workspaceManager),
            RunTerminalTool(actionHub: agentActionHub),
            GitOpTool(actionHub: agentActionHub),
        ]
        if let memoryService {
            _ = agentContextHub.register(appID: "host.memory") {
                MemoryContextSource.snapshot(from: memoryService)
            }
            agentTools.append(MemoryWriteTool(service: memoryService))
            agentTools.append(MemorySearchTool(service: memoryService))
        }

        // MCP (M7 Slice 2): configured servers + their live connections. Uses
        // `MCPServerRegistry.defaultClientFactory` (the real stdio/httpSSE transport
        // factory, the one place real transports get instantiated) — tests inject a
        // stub factory instead so the registry core never spawns a process or hits
        // the network. Connecting is kicked off after `environment` exists (below),
        // never awaited here, so a down/misconfigured server can't delay launch.
        let mcpServerRegistry = MCPServerRegistry(configStore: mcpConfigStore)

        let agentToolRegistry = AgentToolRegistry(
            tools: agentTools,
            dynamicTools: { [weak mcpServerRegistry] in mcpServerRegistry?.currentTools() ?? [] })
        let modelCatalogService = ModelCatalogService(http: URLSessionDataHTTPClient())
        let agentStore = AgentStore(persistence: persistence)

        // Model Router / Usage / Failover wiring (M7 Slice 5b). Every one of these is
        // degrade-don't-crash: `AgentSession` treats them as optional and falls back to
        // pre-Slice-5b behavior (config.current model, single connection, no command
        // interception) if any were nil, mirroring the Slice 1 pattern.
        let modelCatalog = ModelCatalog()
        let modelPriceTable = ModelPriceTable()
        let routerOutcomeStore = RouterOutcomeStore(persistence: persistence)
        let modelRouter = ModelRouter(catalog: modelCatalog, outcomes: routerOutcomeStore)
        let usageTracker = UsageTracker(persistence: persistence, prices: modelPriceTable)
        let runtimeOptionsStore = RuntimeOptionsStore(persistence: persistence)
        let localModelProbe = LocalModelProbe(catalog: modelCatalogService)
        // Async-refreshed reachability cache — see `LocalModelAvailability`. Kicked off
        // (initial + periodic) below, once `connectionStore`/`localModelProbe` exist.
        let localModelAvailability = LocalModelAvailability()
        let authProfileStore = AuthProfileStore(persistence: persistence, secrets: secrets)

        // Candidates = every configured connection's curated model list, resolved
        // against the bundled `ModelCatalog` for tier/capability metadata (falling back
        // to a conservative cheap-paid/tool-use-only descriptor for a model the catalog
        // doesn't recognize yet). Synchronous by design (`candidatesProvider` is called
        // once per turn from `resolveTurn`) — live discovery (`localModelProbe`,
        // `modelCatalogService`) is async and is not woven directly into the fetch, but
        // its OUTPUT (`localModelAvailability.reachableConnectionIDs`, refreshed
        // out-of-band) IS consulted synchronously here to drop LOCAL candidates whose
        // server isn't currently reachable — otherwise a down Ollama/LM Studio gets
        // picked free-first and every turn fails with "Could not connect to the server."
        let candidatesProvider: @MainActor () -> [RouterCandidate] = { [connectionStore, modelCatalog, localModelProbe, localModelAvailability] in
            let all = connectionStore.connections.flatMap { connection -> [RouterCandidate] in
                ProviderPreset.preset(id: connection.presetID).curatedModels.map { modelID in
                    RouterCandidate(
                        connectionID: connection.id, model: modelID,
                        descriptor: modelCatalog.descriptor(for: modelID)
                            ?? ModelDescriptor(id: modelID, tier: .cheapPaid, contextWindow: 128_000, capabilities: [.toolUse]))
                }
            }
            return RouterOrdering.filterReachableCandidates(
                all,
                reachableLocalConnectionIDs: localModelAvailability.reachableConnectionIDs,
                isLocalConnection: { id in
                    connectionStore.connections.first(where: { $0.id == id }).map(localModelProbe.isLocal) ?? false
                }
            )
        }

        let commandRegistry = CommandRegistry(builtins: BuiltinCommands.make(
            runtime: runtimeOptionsStore, usage: usageTracker, router: modelRouter, catalog: modelCatalog))

        let agentSession = AgentSession(
            providerFor: { (connection: Connection) -> LLMProvider in
                switch connection.kind {
                case .claude: return ClaudeProvider(http: streamingHTTP)
                case .openAICompatible: return OpenAICompatibleProvider(http: streamingHTTP, baseURL: connection.baseURL)
                case .gemini: return GeminiProvider(http: streamingHTTP, baseURL: connection.baseURL)
                }
            },
            connections: connectionStore,
            config: agentConfigStore,
            context: agentContextService,
            registry: agentToolRegistry,
            permissions: agentPermissionStore,
            memory: memoryService,
            agents: agentStore,
            router: modelRouter,
            usage: usageTracker,
            runtime: runtimeOptionsStore,
            commands: commandRegistry,
            authProfiles: authProfileStore,
            candidatesProvider: candidatesProvider,
            isLocalConnection: { [localModelProbe] connection in localModelProbe.isLocal(connection) },
            mcpTrust: { [weak mcpServerRegistry] name in mcpServerRegistry?.isToolTrusted(name) ?? false }
        )

        let environment = AppEnvironment(
            persistence: persistence,
            secrets: secrets,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: LauncherStore(registry: registry, workspaceManager: workspaceManager, appAppearanceStore: appAppearanceStore),
            connectionStore: connectionStore,
            appStore: appStore,
            appStoreStore: appStoreStore,
            appIconStore: appIconStore,
            shortcutStore: ShortcutStore(persistence: persistence),
            quitCoordinator: QuitCoordinator(persistence: persistence, terminator: AppKitTerminationReplier()),
            generalSettingsStore: generalSettingsStore,
            appAppearanceStore: appAppearanceStore,
            skySettingsStore: skySettingsStore,
            sounds: sounds,
            agentContextHub: agentContextHub,
            agentActionHub: agentActionHub,
            agentConfigStore: agentConfigStore,
            agentPermissionStore: agentPermissionStore,
            agentContextSettingsStore: agentContextSettingsStore,
            agentContextService: agentContextService,
            agentStore: agentStore,
            agentSession: agentSession,
            mcpServerRegistry: mcpServerRegistry,
            modelCatalogService: modelCatalogService,
            modelCatalog: modelCatalog,
            modelPriceTable: modelPriceTable,
            usageTracker: usageTracker,
            routerOutcomeStore: routerOutcomeStore,
            modelRouter: modelRouter,
            runtimeOptionsStore: runtimeOptionsStore,
            localModelProbe: localModelProbe,
            localModelAvailability: localModelAvailability,
            authProfileStore: authProfileStore,
            commandRegistry: commandRegistry,
            memoryService: memoryService
        )

        // Kick the local-reachability cache: an immediate refresh so the very
        // first turn already reflects reality (best-effort — a turn started
        // before this completes just sees the cache's initial empty state,
        // which is safe: local candidates are dropped, not hung on), then a
        // 30s repeating loop so a server started/stopped mid-session is
        // picked up without requiring a model-picker visit. Runs for the
        // process lifetime of `environment`, mirroring other bootstrap-owned
        // background loops in this app (e.g. sound/theme observers).
        Task { [weak connectionStore, weak localModelProbe] in
            while !Task.isCancelled {
                guard let connectionStore, let localModelProbe else { return }
                await localModelAvailability.refresh(
                    connections: connectionStore.connections, probe: localModelProbe,
                    tokenFor: { connectionStore.token(for: $0) })
                try? await Task.sleep(for: .seconds(30))
            }
        }

        // Connect enabled MCP servers off the launch path: `connectEnabled()` is async
        // and per-server bounded/degrade-don't-crash (see `MCPServerRegistry`), but
        // launch itself must never block on a slow or down server, so this is fired
        // from an unawaited `Task` rather than run synchronously in `bootstrap()`.
        // Tools/trust populate as servers come up; a down server just never appears.
        Task { [weak mcpServerRegistry] in
            await mcpServerRegistry?.connectEnabled()
        }

        // Terminal ships as an App Store plugin (AinkradTerminal), not compiled in.
        // Still migrate any pre-4a host-global settings into its scoped store so the
        // installed plugin sees the user's existing configuration.
        let terminalHost = HostServicesImpl(appID: "terminal", dataRootURL: pluginDataRoot,
                                            secretStore: secrets, themeManager: themeManager,
                                            hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                                            declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)
        TerminalSettingsMigration.runIfNeeded(
            legacyRawPayload: { (persistence as? FileDocumentStore)?.rawPayloadData(forID: $0) },
            scoped: terminalHost.documents, defaults: defaults)

        // Assistant is a host-embedded built-in (its views read `AppEnvironment`
        // directly), scoped like any other app for its documents/secrets/theme/context.
        let assistantHost = HostServicesImpl(appID: "assistant", dataRootURL: pluginDataRoot,
                                             secretStore: secrets, themeManager: themeManager,
                                             hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                                             declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        let loaded = loader.loadAll(from: pluginDirs)
        registry.install(
            builtIn: [
                RegisteredApp.builtIn(
                    AssistantApp.self,
                    summary: "Your in-workspace AI assistant — chat about your code, run gated tools, and drive the terminal and git without leaving Ainkrad.",
                    host: assistantHost,
                    // Reading `surfaceOpacity` inside this closure — invoked
                    // synchronously from `TileLayoutView.hasTranslucentPane`
                    // and `BlockView.headerBackground` during their view
                    // bodies — registers an @Observable dependency, so dialing
                    // the slider live re-evaluates the backdrop + header.
                    chromeFillOverride: {
                        AssistantApp.surfaceFill(
                            opacity: appAppearanceStore.surfaceOpacity("assistant"),
                            base: themeManager.tokens.background
                        )
                    }
                )
            ],
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

        environment.launcherStore.presentOverlay = { [weak environment] appID in
            environment?.presentedOverlayAppID = appID
        }

        // Captures `[weak environment]` (rather than `[weak workspaceManager]`,
        // as pre-Slice-3) so it can also clear `presentedOverlayAppID` — any
        // app opening (tiled or via this hub) dismisses a summoned plugin
        // overlay, mirroring the Settings/App Store overlays' dismiss-on-open.
        pluginLaunchHub.setOpenHandler { [weak environment] appID in
            guard let environment else { return }
            let declared = environment.registry.allApps.first { $0.id == appID }?.presentation ?? .pane
            let effective = environment.appAppearanceStore.presentationOverride(appID) ?? declared
            if effective == .overlay {
                environment.presentedOverlayAppID = appID
            } else {
                environment.workspaceManager.activeWorkspace.tileLayout.openApp(appID)
                environment.presentedOverlayAppID = nil
            }
        }

        Log.app.info("AppEnvironment bootstrapped with \(registry.allApps.count) registered app(s)")
        return environment
    }
}
