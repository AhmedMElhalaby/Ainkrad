import Foundation
import SwiftUI
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
    /// Shared per-connection live-discovered models — read by the composer's model
    /// picker AND the Auto router's `candidatesProvider`, so a live-discovered model
    /// can be selected and auto-routed. Curated presets are the fallback only.
    let discoveredModelsStore: DiscoveredModelsStore
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
    /// M7 Slice 3b (Autonomy: scheduling/triggers) — the persisted `AgentSchedule`s
    /// the `ScheduleUIView` create/edit list reads/writes, `scheduleRunner` (time
    /// triggers) and `fileChangeWatcher`+`triggerDispatcher` (event triggers) fire
    /// against. Retained here (not just a bootstrap local) for the same reason as
    /// `runManager` above: `ScheduleUIView` and any future surface must bind to the
    /// SAME live store a background trigger updates.
    let scheduleStore: ScheduleStore
    /// M7 Slice 3b: fires enabled `.time` schedules on a 60s tick against `runManager`.
    /// Started once in `bootstrap()`; retained here so it isn't deallocated (which
    /// would invalidate its `Timer`) once `bootstrap()` returns.
    let scheduleRunner: ScheduleRunner
    /// M7 Slice 3b: rate-limited fan-in for event-triggered schedules (file/git
    /// change, webhook) — both `fileChangeWatcher`'s callbacks and (once started)
    /// `WebhookServer` route through `fire(_:)` here.
    let triggerDispatcher: TriggerDispatcher
    /// M7 Slice 3b: FSEvents-backed watcher registered (in `bootstrap()`) for every
    /// enabled `.fileChange`/`.gitChange` schedule, routing `onChange` into
    /// `triggerDispatcher.fire`. Retained so its `FSEventStreamRef`s stay alive.
    let fileChangeWatcher: FileChangeWatcher
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
    /// M7 Slice 7: menu-bar (status item) presence — derived run summary + open
    /// state — wrapping `runManager` via `RunManagerMenuBarAdapter`. Constructed
    /// in `bootstrap()` alongside `runManager` so both share the same instance.
    let menuBarPresence: MenuBarPresence
    /// M7 Slice 7 (Live Canvas): the spatial-card store `CanvasApp`'s pane binds
    /// to and `canvas_render` (appended to the shared `agentToolRegistry` in
    /// `bootstrap()`) mutates — same one-instance-shared-everywhere pattern as
    /// `runManager`/`scheduleStore` above.
    let canvasStore: CanvasStore
    /// M7 Slice 8 (Voice): push-to-talk + file-transcription facade. Constructed
    /// after `agentSession` (both in `bootstrap()` and here) so
    /// `attachSession(_:)` can wire voice auto-send through the real session's
    /// `send(_:)` — voice is not a privileged input channel.
    let voiceService: VoiceService
    /// Owns the `NSStatusItem`/popover for the app's lifetime. `var`/optional
    /// (not an `init` param) because its content closure captures `self` —
    /// it's built in `bootstrap()` right after `environment` itself exists,
    /// then installed/torn down by `AinkradAppDelegate`.
    var menuBarController: MenuBarController?
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
        discoveredModelsStore: DiscoveredModelsStore,
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
        scheduleStore: ScheduleStore,
        scheduleRunner: ScheduleRunner,
        triggerDispatcher: TriggerDispatcher,
        fileChangeWatcher: FileChangeWatcher,
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
        skillCommandStore: SkillCommandStore,
        menuBarPresence: MenuBarPresence,
        canvasStore: CanvasStore,
        voiceService: VoiceService
    ) {
        self.persistence = persistence
        self.secrets = secrets
        self.registry = registry
        self.themeManager = themeManager
        self.workspaceManager = workspaceManager
        self.launcherStore = launcherStore
        self.connectionStore = connectionStore
        self.discoveredModelsStore = discoveredModelsStore
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
        self.scheduleStore = scheduleStore
        self.scheduleRunner = scheduleRunner
        self.triggerDispatcher = triggerDispatcher
        self.fileChangeWatcher = fileChangeWatcher
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
        self.menuBarPresence = menuBarPresence
        self.canvasStore = canvasStore
        self.voiceService = voiceService
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
        let (
            persistence, secrets, registry, themeManager, workspaceManager, documentsRoot, pluginDirs,
            pluginDataRoot, retainedDataRoot, agentContextHub, agentActionHub, pluginLaunchHub,
            appAppearanceStore, loader, mcpConfigStore, skillsRoot, appStore, appStoreStore, appIconStore,
            generalSettingsStore, skySettingsStore, sounds, connectionStore, discoveredModelsStore
        ) = bootstrapCoreStores(rootURL: rootURL, defaults: defaults)

        let (
            streamingHTTP, agentConfigStore, agentContextSettingsStore, agentContextService,
            agentPermissionStore, memoryService, lspServerRegistry, editJournal, skillRegistry,
            skillCommandStore, skillWatcher
        ) = bootstrapAgentKitCore(
            persistence: persistence, workspaceManager: workspaceManager, agentContextHub: agentContextHub,
            skillsRoot: skillsRoot, rootURL: rootURL, documentsRoot: documentsRoot)

        let (
            sandboxProfileStore, cloudCredentialsStore, executionRouter, agentTools, mcpServerRegistry, canvasStore
        ) = bootstrapExecutionAndTools(
            persistence: persistence, secrets: secrets, lspServerRegistry: lspServerRegistry,
            editJournal: editJournal, workspaceManager: workspaceManager, agentActionHub: agentActionHub,
            agentContextHub: agentContextHub, memoryService: memoryService, mcpConfigStore: mcpConfigStore,
            skillRegistry: skillRegistry)

        let (
            modelCatalogService, agentStore, modelCatalog, modelPriceTable, routerOutcomeStore, modelRouter,
            usageTracker, runtimeOptionsStore, localModelProbe, localModelAvailability, authProfileStore,
            candidatesProvider, commandRegistry
        ) = bootstrapModelRouting(
            persistence: persistence, secrets: secrets, connectionStore: connectionStore,
            discoveredModelsStore: discoveredModelsStore)

        let (
            subagentCoordinator, runManager, scheduleStore, scheduleRunner, triggerDispatcher, fileChangeWatcher,
            assistantWorkingDirectory, workspaceFileIndex, agentSession, voiceService, menuBarPresence
        ) = bootstrapAgentSessionAndRuns(
            persistence: persistence, streamingHTTP: streamingHTTP, connectionStore: connectionStore,
            agentConfigStore: agentConfigStore, agentContextService: agentContextService,
            agentPermissionStore: agentPermissionStore, agentStore: agentStore, editJournal: editJournal,
            memoryService: memoryService, modelRouter: modelRouter, executionRouter: executionRouter,
            candidatesProvider: candidatesProvider, usageTracker: usageTracker,
            runtimeOptionsStore: runtimeOptionsStore, commandRegistry: commandRegistry,
            authProfileStore: authProfileStore, localModelProbe: localModelProbe,
            agentActionHub: agentActionHub, agentTools: agentTools, mcpServerRegistry: mcpServerRegistry,
            skillRegistry: skillRegistry, skillCommandStore: skillCommandStore)

        let environment = AppEnvironment(
            persistence: persistence,
            secrets: secrets,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: LauncherStore(registry: registry, workspaceManager: workspaceManager, appAppearanceStore: appAppearanceStore),
            connectionStore: connectionStore,
            discoveredModelsStore: discoveredModelsStore,
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
            scheduleStore: scheduleStore,
            scheduleRunner: scheduleRunner,
            triggerDispatcher: triggerDispatcher,
            fileChangeWatcher: fileChangeWatcher,
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
            skillCommandStore: skillCommandStore,
            menuBarPresence: menuBarPresence,
            canvasStore: canvasStore,
            voiceService: voiceService
        )

        finalizeBootstrap(
            environment: environment, connectionStore: connectionStore, localModelProbe: localModelProbe,
            localModelAvailability: localModelAvailability, mcpServerRegistry: mcpServerRegistry,
            lspServerRegistry: lspServerRegistry, persistence: persistence, secrets: secrets,
            themeManager: themeManager, agentContextHub: agentContextHub, agentActionHub: agentActionHub,
            pluginLaunchHub: pluginLaunchHub, appAppearanceStore: appAppearanceStore,
            pluginDataRoot: pluginDataRoot, pluginDirs: pluginDirs, loader: loader, registry: registry,
            workspaceManager: workspaceManager, defaults: defaults
        )

        return environment
    }
}
