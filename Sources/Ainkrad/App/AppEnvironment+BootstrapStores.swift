import Foundation
import AinkradAppKit
import AinkradHostRuntime

/// `AppEnvironment.bootstrap(rootURL:defaults:)` split into cohesive helpers
/// (M7 finalize Wave D, D2) — this file holds the first two sequential
/// blocks: core persistence/plugin/appearance stores, then the AgentKit
/// core services (memory, LSP, skills, edit journal). Each helper is a pure
/// value-construction step: it takes the already-built deps it needs and
/// returns the values the next block consumes, mirroring `bootstrap()`'s
/// original sequential wiring exactly — no behavior change, only relocation.
extension AppEnvironment {
    /// First block of `bootstrap()`: the file/keychain-backed persistence
    /// layer, the legacy-defaults migration, plugin loading/App Store
    /// plumbing, app appearance/icon/sound stores, and the connection +
    /// discovered-models stores.
    static func bootstrapCoreStores(rootURL: URL?, defaults: UserDefaults) -> (
        persistence: PersistenceStore,
        secrets: SecretStore,
        registry: BuiltInAppRegistry,
        themeManager: ThemeManager,
        workspaceManager: WorkspaceManager,
        documentsRoot: URL,
        pluginDirs: [URL],
        pluginDataRoot: URL,
        retainedDataRoot: URL,
        agentContextHub: AgentContextRegistryHub,
        agentActionHub: AgentActionRegistryHub,
        pluginLaunchHub: PluginLaunchHub,
        appAppearanceStore: AppAppearanceStore,
        webSearchSettingsStore: WebSearchSettingsStore,
        mediaSettingsStore: MediaSettingsStore,
        sessionShareStore: SessionShareStore,
        loader: PluginLoader,
        mcpConfigStore: MCPServerConfigStore,
        skillsRoot: URL,
        appStore: AppStoreService,
        appStoreStore: AppStoreStore,
        appIconStore: AppIconStore,
        generalSettingsStore: GeneralSettingsStore,
        skySettingsStore: SkySettingsStore,
        sounds: SoundPlaying,
        connectionStore: ConnectionStore,
        discoveredModelsStore: DiscoveredModelsStore
    ) {
        let persistence = FileDocumentStore(rootURL: rootURL ?? FileDocumentStore.defaultDocumentsURL())
        // An injected root means a test context; never touch the real Keychain there.
        let secrets: SecretStore = rootURL == nil ? KeychainSecretStore() : InMemorySecretStore()

        // One-time import of M1's UserDefaults settings before any store reads.
        LegacyUserDefaultsMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let registry = BuiltInAppRegistry(persistence: persistence)
        let themeManager = ThemeManager(persistence: persistence)

        let workspaceManager = WorkspaceManager()

        // Plugin loading/App Store plumbing needs to exist before
        // `AppEnvironment` is constructed, since `appStore` is one of its
        // stored dependencies.
        let documentsRoot = rootURL ?? FileDocumentStore.defaultDocumentsURL()
        // `DevPlugins/` is an UNMANAGED sideload directory: anything that can
        // write a `.bundle` there gets in-process execution. It is scanned in
        // Debug only (`PluginTrust.scansDevPluginsDirectory`); in Release the
        // sole entry path is a catalog install, which the signature policy
        // below then gates. Order matters — dev last, so a sideloaded build
        // overrides an installed release of the same app (see
        // `PluginLoader.loadAll`'s dedup).
        var pluginDirs = [documentsRoot.appendingPathComponent("Plugins", isDirectory: true)]
        if PluginTrust.scansDevPluginsDirectory {
            pluginDirs.append(documentsRoot.appendingPathComponent("DevPlugins", isDirectory: true))
        }
        let pluginDataRoot = documentsRoot.appendingPathComponent("PluginData", isDirectory: true)
        let retainedDataRoot = documentsRoot.appendingPathComponent("RetainedPluginData", isDirectory: true)
        let agentContextHub = AgentContextRegistryHub()
        let agentActionHub = AgentActionRegistryHub()
        let pluginLaunchHub = PluginLaunchHub()
        let appAppearanceStore = AppAppearanceStore(persistence: persistence)
        let webSearchSettingsStore = WebSearchSettingsStore(persistence: persistence)
        let mediaSettingsStore = MediaSettingsStore(persistence: persistence)
        let sessionShareStore = SessionShareStore(
            persistence: persistence,
            baseDirectory: rootURL.map { $0.appendingPathComponent("Shares", isDirectory: true) }
                ?? SessionShareStore.defaultDirectory())
        // Trust policy is chosen by build configuration in ONE place
        // (`PluginTrust`), so the permissive dev policy is compiled out of
        // Release entirely and no wiring mistake can ship it.
        let loader = PluginLoader(signaturePolicy: PluginTrust.policyForCurrentBuild(), minSupportedAPIVersion: GenerationSupport.minSupported) { appID, declaredPresentation in
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
        // Mirrors `memoryRoot` below: when a test injects `rootURL`, Skills lives
        // under that isolated root rather than the real Application Support path,
        // so `make test` never touches (or scans) the developer's real skill
        // library. The installer and the registry share this same root — they
        // read/write the same on-disk `Skills/` tree.
        let skillsRoot = rootURL != nil
            ? documentsRoot.appendingPathComponent("Skills", isDirectory: true)
            : SkillPaths.defaultRoot()
        let skillInstaller = SkillInstaller(
            http: URLSessionHTTPClient(), paths: SkillPaths(root: skillsRoot),
            persistence: persistence)
        let appStore = AppStoreService(catalog: catalogService, installer: installer,
                                       mcpInstaller: mcpInstaller, persistence: persistence,
                                       skillInstaller: skillInstaller)
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

        // Shared per-connection live-discovered models (picker + router candidates).
        // Prune entries for connections that no longer exist so a deleted
        // connection's stale list doesn't linger.
        let discoveredModelsStore = DiscoveredModelsStore(persistence: persistence)
        discoveredModelsStore.prune(keeping: Set(connectionStore.connections.map(\.id)))

        return (
            persistence, secrets, registry, themeManager, workspaceManager, documentsRoot, pluginDirs,
            pluginDataRoot, retainedDataRoot, agentContextHub, agentActionHub, pluginLaunchHub,
            appAppearanceStore, webSearchSettingsStore, mediaSettingsStore, sessionShareStore, loader, mcpConfigStore, skillsRoot, appStore, appStoreStore, appIconStore,
            generalSettingsStore, skySettingsStore, sounds, connectionStore, discoveredModelsStore
        )
    }

    /// Second block of `bootstrap()`: the AgentKit core services — shared
    /// streaming HTTP client, agent config/context/permission stores, the
    /// degrade-don't-crash memory service, the LSP registry, the edit
    /// journal, and the Skills subsystem (registry + command store + watcher).
    static func bootstrapAgentKitCore(
        persistence: PersistenceStore,
        workspaceManager: WorkspaceManager,
        agentContextHub: AgentContextRegistryHub,
        skillsRoot: URL,
        rootURL: URL?,
        documentsRoot: URL
    ) -> (
        streamingHTTP: URLSessionStreamingHTTPClient,
        agentConfigStore: AgentConfigStore,
        agentContextSettingsStore: AgentContextSettingsStore,
        agentContextService: AgentContextService,
        agentPermissionStore: AgentPermissionStore,
        memoryService: MemoryService?,
        lspServerRegistry: LSPServerRegistry,
        editJournal: EditJournal,
        skillRegistry: SkillRegistry,
        skillCommandStore: SkillCommandStore,
        skillWatcher: SkillWatcher
    ) {
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

        // LSP (M7 Slice 2): configured language servers backing `EditFileTool`'s
        // advisory diagnostics/formatting. Uses `LSPServerRegistry.defaultClientFactory`
        // (the real stdio transport factory) — tests inject a stub factory instead so the
        // registry core never spawns a real language-server process. PATH autodetection
        // (below, after `environment` exists) shells out to `which` per known server, so
        // it's seeded from an unawaited `Task`, never here, so a slow/missing binary can't
        // delay launch.
        let lspServerRegistry = LSPServerRegistry(persistence: persistence)

        // M7 Slice 3 (Autonomy) Task 10/11 — the per-session edit ledger `EditFileTool`
        // records into, so a turn's file edits can be undone via `/undo`.
        let editJournal = EditJournal()

        // Skills (M7 Slice 4): construction is synchronous but cheap — `reload()`
        // only lists `Skills/`'s immediate subdirectories and parses their small
        // SKILL.md files, the same order of work `MemoryService`'s FTS open and
        // `PluginLoader.loadAll` already do synchronously at this exact point in
        // bootstrap. A malformed/unreadable skill is skipped and recorded in
        // `loadErrors` (never thrown), so a bad skill can't take launch down.
        // `marketplaceNames` reads the same `InstalledPluginsDocument` plugins use —
        // `SkillInstaller.install` records installed skills there keyed by appID —
        // so a skill installed via the marketplace loads tagged `.marketplace`.
        let skillRegistry = SkillRegistry(
            paths: SkillPaths(root: skillsRoot),
            marketplaceNames: { [weak persistence = persistence] in
                Set((persistence?.load(InstalledPluginsDocument.self)?.installed.keys).map(Array.init) ?? [])
            })
        let skillCommandStore = SkillCommandStore(persistence: persistence)
        // File-watch reload (Task 14): a user editing/adding/removing a
        // SKILL.md directly in Skills/ (outside the app) is picked up live.
        // Captures `skillRegistry` weakly — the watcher never extends its
        // lifetime, only reacts while it's alive.
        let skillWatcher = SkillWatcher(paths: SkillPaths(root: skillsRoot)) { [weak skillRegistry] in
            skillRegistry?.reload()
        }
        skillWatcher.start()

        return (
            streamingHTTP, agentConfigStore, agentContextSettingsStore, agentContextService,
            agentPermissionStore, memoryService, lspServerRegistry, editJournal, skillRegistry,
            skillCommandStore, skillWatcher
        )
    }
}
