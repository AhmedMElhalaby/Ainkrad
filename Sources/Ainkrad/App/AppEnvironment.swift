import Foundation
import AinkradAppKit

/// Persisted root directory for the `@`-mention file index (M7 Slice 5c Task 22).
/// Defaults to the user's home directory until a later folder-picker (Task 22b,
/// not built here) lets the user change it.
struct AssistantWorkspaceSettings: PersistableDocument {
    static let documentID = "assistant-workspace"
    var workingDirectoryPath: String

    init(workingDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.workingDirectoryPath = workingDirectoryPath
    }
}

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
    /// M7 Slice 6 (Security & Sandboxing): the persisted store of built-in +
    /// user-defined `SandboxProfile`s the router resolves against.
    let sandboxProfileStore: SandboxProfileStore
    /// M7 Slice 6 (Security & Sandboxing): chooses backend + `SandboxProfile`
    /// per trust tier. Stored here (not just a local in `bootstrap()`) so it
    /// outlives the `unowned` reference `RunTerminalTool` holds to it.
    let executionRouter: ExecutionRouter
    /// M7 Slice 6 (Security & Sandboxing, Task 16): Keychain-backed per-provider
    /// cloud credentials (Modal token, etc). Cloud stays opt-in per-Agent
    /// (`AgentExecutionPolicy.allowCloud`) — storing a credential here never by
    /// itself enables cloud routing (see `ExecutionRouter`).
    let cloudCredentialsStore: CloudCredentialsStore
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
    /// M7 Slice 2 (LSP) — owns live language-server connections; feeds
    /// `EditQuality` advisory diagnostics/formatting for `EditFileTool`. See
    /// `bootstrap()` for the non-blocking first-launch autodetect seed.
    let lspServerRegistry: LSPServerRegistry
    /// M7 Slice 3 (Autonomy) Task 11 wiring: the per-session edit ledger `agentSession`
    /// (and every background run's headless session) journals into, the subagent
    /// fan-out coordinator `spawn_subagent` delegates through, and the Runs monitor's
    /// observable queue/active/history engine — retained here so `RunsPanelView` and
    /// any future surface can bind to the SAME live `RunManager` a background run
    /// updates.
    let editJournal: EditJournal
    let subagentCoordinator: SubagentCoordinator
    let runManager: RunManager
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
    /// The root directory `workspaceFileIndex` was built from — persisted via
    /// `AssistantWorkspaceSettings`, defaulting to the home directory. Task 22b's
    /// folder-picker will add a setter that persists a new root and rebuilds the
    /// index; not built here.
    let assistantWorkingDirectory: URL
    /// Fuzzy file index over `assistantWorkingDirectory`, backing the `@`-mention
    /// overlay Task 22b builds. Refreshed once asynchronously at bootstrap.
    let workspaceFileIndex: WorkspaceFileIndex
    /// The assistant memory subsystem (M7 Slice 1). `nil` when the FTS index
    /// couldn't be opened at launch — the app degrades to memory-less rather
    /// than crashing (see `bootstrap()`).
    let memoryService: MemoryService?
    /// The Skills subsystem (M7 Slice 4): active-skill registry backing
    /// `use_skill`/`propose_skill`, the skill-index context source, and the
    /// skill `/name` slash commands.
    let skillRegistry: SkillRegistry
    /// CRUD over `/name` → skill-name command bindings; registers its
    /// `SlashCommand`s into `commandRegistry` at bootstrap.
    let skillCommandStore: SkillCommandStore
    /// Watches `Skills/` on disk (Task 14) and reloads `skillRegistry` when the
    /// user adds/edits/removes a `SKILL.md` outside the app — retained for the
    /// process lifetime so its `DispatchSource` stays alive; see `bootstrap()`
    /// for where it's started.
    let skillWatcher: SkillWatcher
    /// Skill `/name` command names currently registered into `commandRegistry`
    /// — tracked so `resyncSkillCommands()` (Task 13) knows exactly which
    /// entries to drop before re-registering the current binding set, without
    /// ever touching a builtin name it didn't register itself.
    private var registeredSkillCommandNames: Set<String> = []
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
        sandboxProfileStore: SandboxProfileStore,
        executionRouter: ExecutionRouter,
        cloudCredentialsStore: CloudCredentialsStore,
        agentConfigStore: AgentConfigStore,
        agentPermissionStore: AgentPermissionStore,
        agentContextSettingsStore: AgentContextSettingsStore,
        agentContextService: AgentContextService,
        agentStore: AgentStore,
        agentSession: AgentSession,
        mcpServerRegistry: MCPServerRegistry,
        lspServerRegistry: LSPServerRegistry,
        editJournal: EditJournal,
        subagentCoordinator: SubagentCoordinator,
        runManager: RunManager,
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
        assistantWorkingDirectory: URL,
        workspaceFileIndex: WorkspaceFileIndex,
        memoryService: MemoryService?,
        skillRegistry: SkillRegistry,
        skillWatcher: SkillWatcher,
        skillCommandStore: SkillCommandStore
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
        self.sandboxProfileStore = sandboxProfileStore
        self.executionRouter = executionRouter
        self.cloudCredentialsStore = cloudCredentialsStore
        self.agentConfigStore = agentConfigStore
        self.agentPermissionStore = agentPermissionStore
        self.agentContextSettingsStore = agentContextSettingsStore
        self.agentContextService = agentContextService
        self.agentStore = agentStore
        self.agentSession = agentSession
        self.mcpServerRegistry = mcpServerRegistry
        self.lspServerRegistry = lspServerRegistry
        self.editJournal = editJournal
        self.subagentCoordinator = subagentCoordinator
        self.runManager = runManager
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
        self.assistantWorkingDirectory = assistantWorkingDirectory
        self.workspaceFileIndex = workspaceFileIndex
        self.memoryService = memoryService
        self.skillRegistry = skillRegistry
        self.skillWatcher = skillWatcher
        self.skillCommandStore = skillCommandStore
        // Seeds `registeredSkillCommandNames` with whatever bootstrap already
        // registered (see the loop right after `commandRegistry` is built),
        // so the very first `resyncSkillCommands()` call — triggered by a
        // bind/unbind from the Skills manager UI — knows what to drop.
        self.registeredSkillCommandNames = Set(skillCommandStore.slashCommands(registry: skillRegistry).map(\.name))
    }

    /// Re-syncs the live `commandRegistry` with the current
    /// `skillCommandStore` bindings. Bootstrap (`bootstrap()` below) only
    /// registers skill `/name` commands once, at launch — a bind/unbind made
    /// afterward via the Skills manager UI (Task 13) would otherwise sit
    /// invisibly in `skillCommandStore` until the next relaunch. Call this
    /// after every bind/unbind so `/name` starts/stops working immediately.
    /// Never touches a builtin: it only unregisters names THIS method
    /// previously registered, then re-registers the current binding set
    /// (`slashCommands(registry:)` independently filters out any name that
    /// collides with a builtin, as defense in depth).
    func resyncSkillCommands() {
        for name in registeredSkillCommandNames {
            commandRegistry.unregister(name: name)
        }
        let commands = skillCommandStore.slashCommands(registry: skillRegistry)
        for command in commands {
            commandRegistry.register(command)
        }
        registeredSkillCommandNames = Set(commands.map(\.name))
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

        // M7 Slice 6: every backend is registered by its own kind — host
        // (trusted-main only, unchanged), seatbelt (macOS sandbox-exec),
        // docker + ssh (feature-detected: `isAvailable()` self-reports false
        // when the CLI/daemon/connection isn't present). Construction here
        // never spawns a process or blocks the launch/main-actor path —
        // `DockerBackend`/`SSHBackend`/`SeatbeltBackend` only stat a path or
        // check a stored `nil` connection at init; the actual (bounded,
        // async) availability probe happens lazily inside `router.route`,
        // per call. No backend is registered as a fallback for another kind —
        // an unregistered/unavailable backend fails closed in
        // `ExecutionRouter.route`, never substituting host.
        //
        // `.cloud` (Task 16): `ModalCloudBackend.isAvailable()` self-reports
        // false until a Modal token is stored via `cloudCredentialsStore` —
        // and even once configured, `AgentExecutionPolicy.allowCloud` (never
        // a tier default; see `ExecutionRouter.route`) is still required
        // before this backend is even attempted, and its `remoteExec` driver
        // is a fail-closed research stub (see `ModalCloudBackend`). Cloud
        // never becomes a working "just works" path from this wiring alone.
        let sandboxProfileStore = SandboxProfileStore(persistence: persistence)
        let cloudCredentialsStore = CloudCredentialsStore(secrets: secrets)
        let executionRouter = ExecutionRouter(
            profiles: sandboxProfileStore,
            backends: [
                .host: HostBackend(),
                .seatbelt: SeatbeltBackend(),
                .docker: DockerBackend(),
                .ssh: SSHBackend(connection: nil),   // Leyline connection wired when AinkradSSH lands
                .cloud: ModalCloudBackend(credentials: cloudCredentialsStore),
            ])

        var agentTools: [any AgentTool] = [
            ReadFileTool(),
            EditFileTool(editQuality: EditQuality(registry: lspServerRegistry), journal: editJournal),
            WorkspaceControlTool(workspaces: workspaceManager),
            RunTerminalTool(actionHub: agentActionHub, router: executionRouter),
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

        // Skill-index context source (Task 5) + agent-facing tools (Task 6/7).
        // Both hold the mutable `skillRegistry` reference and read its live set at
        // execute-time, so a reload (install/approve/discard) is reflected without
        // re-registering anything here.
        _ = agentContextHub.register(appID: "host.skills") {
            SkillIndexContextSource.snapshot(from: skillRegistry)
        }
        agentTools.append(UseSkillTool(registry: skillRegistry))
        agentTools.append(ProposeSkillTool(registry: skillRegistry))

        // NOTE: `agentToolRegistry` (the registry the main `agentSession` and every
        // background run's headless session bind to) is built further below, AFTER
        // `spawn_subagent` is appended to `agentTools` — see the Slice 3 wiring block
        // once the Slice 5b Model Router / `candidatesProvider` it needs exist. Its
        // `dynamicTools` closure surfaces the Slice 2 MCP servers' discovered tools.
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
        // M7 Slice 3 (Autonomy) Task 11: `/stop` interrupts the in-flight turn.
        // `/undo` and `/retry` are already registered as builtins (Task 10).
        commandRegistry.register(SlashCommand(
            name: "stop", summary: "Interrupt the current turn", usage: "/stop") { _, session in
            session.interrupt()
            return .handled(note: "Interrupted.")
        })

        // Single provider-resolution closure, shared by the main `agentSession`, every
        // subagent's child session, and every background run's headless session — one
        // provider construction rule, not three copies that could drift.
        let providerFor: @MainActor (Connection) -> LLMProvider = { connection in
            switch connection.kind {
            case .claude: return ClaudeProvider(http: streamingHTTP)
            case .openAICompatible: return OpenAICompatibleProvider(http: streamingHTTP, baseURL: connection.baseURL)
            case .gemini: return GeminiProvider(http: streamingHTTP, baseURL: connection.baseURL)
            }
        }

        // M7 Slice 3 (Autonomy) Task 11 — wires the whole 3a subsystem live:
        // `spawn_subagent` delegates through `SubagentCoordinator` to the PRODUCTION
        // `AgentSessionSubagentRunner`, whose `makeSession` seam (Task 6's deferred
        // closure) is built here — every child session is UNATTENDED (a requireApproval
        // tool auto-denies rather than parking on a HUD nobody can answer — Task 8's
        // gate) with its router-resolved model PINNED (no router/candidatesProvider
        // passed to the child, so it never re-routes per tool-loop turn).
        let subagentRunner = AgentSessionSubagentRunner(
            allTools: agentTools, agents: agentStore, router: modelRouter,
            candidatesProvider: candidatesProvider,
            makeSession: AppEnvironment.makeSubagentSession(
                providerFor: providerFor, connections: connectionStore,
                agentConfigStore: agentConfigStore, agentContextService: agentContextService,
                agentPermissionStore: agentPermissionStore, agentStore: agentStore))
        let subagentCoordinator = SubagentCoordinator(runner: subagentRunner, maxConcurrent: 4)
        agentTools.append(SpawnSubagentTool(coordinator: subagentCoordinator, agents: agentStore))

        let agentToolRegistry = AgentToolRegistry(
            tools: agentTools,
            dynamicTools: { [weak mcpServerRegistry] in mcpServerRegistry?.currentTools() ?? [] })

        // The Runs monitor's engine: a background run drives a fresh headless
        // `AgentSession` per run (`BackgroundRunRunner`), built `unattended: true` for
        // the same reason as the subagent seam above. Trust tier `.background` (Slice 6,
        // Task 21) isn't wired yet — until then a background run executes on the host's
        // own connections/tools like a normal (but unattended) turn.
        let runNotifier = UserNotificationRunNotifier()
        let runManager = RunManager(
            persistence: persistence,
            runner: BackgroundRunRunner(makeSession: {
                AgentSession(
                    providerFor: providerFor, connections: connectionStore, config: agentConfigStore,
                    context: agentContextService, registry: agentToolRegistry, permissions: agentPermissionStore,
                    agents: agentStore, editJournal: editJournal, unattended: true,
                    router: modelRouter, usage: usageTracker, runtime: runtimeOptionsStore,
                    commands: commandRegistry, authProfiles: authProfileStore,
                    candidatesProvider: candidatesProvider,
                    isLocalConnection: { [localModelProbe] connection in localModelProbe.isLocal(connection) })
            }),
            notifier: runNotifier, maxConcurrent: 2)

        // `@`-mention file index (M7 Slice 5c Task 22a wiring; the overlay UI itself
        // is Task 22b). No first-class "project directory" concept exists yet — default
        // to the home directory until a folder-picker persists a real choice.
        let assistantWorkingDirectory = persistence.load(AssistantWorkspaceSettings.self)
            .map { URL(fileURLWithPath: $0.workingDirectoryPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let workspaceFileIndex = WorkspaceFileIndex(root: assistantWorkingDirectory)
        // `WorkspaceFileIndex` is `@MainActor`; deferring the initial `refresh()` into a
        // `Task` (still main-actor-isolated, since it's spawned from this MainActor-only
        // static func) keeps bootstrap's synchronous path from stalling on a large
        // directory walk, without ever touching the index off its required actor.
        Task { workspaceFileIndex.refresh() }

        // Skill `/name` commands (Task 11): registered after the builtins, through
        // the same seam skill commands are documented to use — `register(_:)`
        // never lets a skill-bound name overwrite a builtin (`SkillCommandStore`
        // already refuses to persist a colliding binding, and
        // `slashCommands(registry:)` filters `BuiltinCommands.reservedNames` again
        // here as defense in depth).
        for command in skillCommandStore.slashCommands(registry: skillRegistry) {
            commandRegistry.register(command)
        }

        let agentSession = AgentSession(
            providerFor: providerFor,
            connections: connectionStore,
            config: agentConfigStore,
            context: agentContextService,
            registry: agentToolRegistry,
            permissions: agentPermissionStore,
            memory: memoryService,
            agents: agentStore,
            editJournal: editJournal,
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
            sandboxProfileStore: sandboxProfileStore,
            executionRouter: executionRouter,
            cloudCredentialsStore: cloudCredentialsStore,
            agentConfigStore: agentConfigStore,
            agentPermissionStore: agentPermissionStore,
            agentContextSettingsStore: agentContextSettingsStore,
            agentContextService: agentContextService,
            agentStore: agentStore,
            agentSession: agentSession,
            mcpServerRegistry: mcpServerRegistry,
            lspServerRegistry: lspServerRegistry,
            editJournal: editJournal,
            subagentCoordinator: subagentCoordinator,
            runManager: runManager,
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
            assistantWorkingDirectory: assistantWorkingDirectory,
            workspaceFileIndex: workspaceFileIndex,
            memoryService: memoryService,
            skillRegistry: skillRegistry,
            skillWatcher: skillWatcher,
            skillCommandStore: skillCommandStore
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

        // Seed autodetected LSP servers off the launch path: `autodetect()` shells out to
        // `which` once per known server (a handful of `Process` spawns), so it runs inside
        // this unawaited `Task` rather than synchronously in `bootstrap()`. `seedIfEmpty`
        // is a no-op once the user has any configs (from a prior autodetect or a manual
        // edit in the LSP config UI), so this only ever does something on first launch.
        Task { [weak lspServerRegistry] in
            let configs = LSPServerRegistry.autodetect()
            await lspServerRegistry?.seedIfEmpty(with: configs)
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

    /// The production `makeSession` closure for `AgentSessionSubagentRunner` (M7 Slice 3
    /// Task 11 — the seam Task 6 deferred). Every child `AgentSession` this builds is:
    /// - **`unattended: true`** — a `.requireApproval` tool auto-denies instead of parking
    ///   on an approval HUD that a headless subagent can never answer (Task 8's gate).
    ///   This can only narrow what a child may do, never approve something the gate
    ///   itself would have blocked.
    /// - **model-PINNED, not re-routed** — the caller (`AgentSessionSubagentRunner.run`)
    ///   already resolved `model` via the Model Router within the spec's budget ceiling;
    ///   handing the child its own `router`/`candidatesProvider` would let it re-route on
    ///   every tool-loop turn and drift off that decision. Instead the resolved model is
    ///   pinned via a private, in-memory `RuntimeOptionsStore` — `resolveTurn`'s degraded
    ///   path (`pin ?? agents?.active.defaultModel ?? config.current.model`) then always
    ///   picks it.
    /// - scoped to the **filtered registry** the runner already narrowed via
    ///   `SubagentRegistryFilter`, with the profile's `instructions` as the base prompt.
    ///
    /// Extracted as a static, standalone-callable factory (rather than inlined in
    /// `bootstrap()`) so a wiring test can exercise it without spinning up the entire
    /// `AppEnvironment`.
    static func makeSubagentSession(
        providerFor: @escaping @MainActor (Connection) -> LLMProvider,
        connections: ConnectionStore,
        agentConfigStore: AgentConfigStore,
        agentContextService: AgentContextService,
        agentPermissionStore: AgentPermissionStore,
        agentStore: AgentStore
    ) -> @MainActor (AgentProfile, AgentToolRegistry, String) -> AgentSession {
        { profile, registry, model in
            let pinned = RuntimeOptionsStore(persistence: InMemoryPersistenceStore())
            pinned.pinModel(model)
            return AgentSession(
                providerFor: providerFor,
                connections: connections,
                config: agentConfigStore,
                context: agentContextService,
                registry: registry,
                permissions: agentPermissionStore,
                basePrompt: profile.instructions.isEmpty ? AgentSession.defaultPrompt : profile.instructions,
                agents: agentStore,
                unattended: true,
                runtime: pinned)
        }
    }
}
