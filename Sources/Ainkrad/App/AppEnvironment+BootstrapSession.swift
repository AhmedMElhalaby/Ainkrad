import Foundation
import AinkradAppKit

/// `AppEnvironment.bootstrap(rootURL:defaults:)` split into cohesive helpers
/// (M7 finalize Wave D, D2) — this file holds the fifth block: subagent
/// wiring (M7 Slice 3 Task 11), the background/headless run subsystem
/// (Slice 3b Task 21), the schedule/trigger subsystem (Slice 3b), the
/// `@`-mention file index, the main `agentSession`, and `voiceService`. Pure
/// value-construction, mirroring `bootstrap()`'s original order exactly.
extension AppEnvironment {
    static func bootstrapAgentSessionAndRuns(
        persistence: PersistenceStore,
        streamingHTTP: URLSessionStreamingHTTPClient,
        connectionStore: ConnectionStore,
        agentConfigStore: AgentConfigStore,
        agentContextService: AgentContextService,
        agentPermissionStore: AgentPermissionStore,
        agentStore: AgentStore,
        editJournal: EditJournal,
        memoryService: MemoryService?,
        modelRouter: ModelRouter,
        executionRouter: ExecutionRouter,
        candidatesProvider: @escaping @MainActor () -> [RouterCandidate],
        usageTracker: UsageTracker,
        runtimeOptionsStore: RuntimeOptionsStore,
        commandRegistry: CommandRegistry,
        authProfileStore: AuthProfileStore,
        localModelProbe: LocalModelProbe,
        agentActionHub: AgentActionRegistryHub,
        agentTools: [any AgentTool],
        mcpServerRegistry: MCPServerRegistry,
        skillRegistry: SkillRegistry,
        skillCommandStore: SkillCommandStore
    ) -> (
        subagentCoordinator: SubagentCoordinator,
        runManager: RunManager,
        scheduleStore: ScheduleStore,
        scheduleRunner: ScheduleRunner,
        triggerDispatcher: TriggerDispatcher,
        fileChangeWatcher: FileChangeWatcher,
        assistantWorkingDirectory: URL,
        workspaceFileIndex: WorkspaceFileIndex,
        agentSession: AgentSession,
        voiceService: VoiceService,
        menuBarPresence: MenuBarPresence
    ) {
        var agentTools = agentTools

        // NOTE: `agentToolRegistry` (the registry the main `agentSession` and every
        // background run's headless session bind to) is built further below, AFTER
        // `spawn_subagent` is appended to `agentTools` — see the Slice 3 wiring block
        // once the Slice 5b Model Router / `candidatesProvider` it needs exist. Its
        // `dynamicTools` closure surfaces the Slice 2 MCP servers' discovered tools.

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
            executionRouter: executionRouter,
            candidatesProvider: candidatesProvider,
            makeSession: AppEnvironment.makeSubagentSession(
                providerFor: providerFor, connections: connectionStore,
                agentConfigStore: agentConfigStore, agentContextService: agentContextService,
                agentPermissionStore: agentPermissionStore, agentStore: agentStore))
        let subagentCoordinator = SubagentCoordinator(runner: subagentRunner, maxConcurrent: 4)
        agentTools.append(SpawnSubagentTool(coordinator: subagentCoordinator, agents: agentStore))
        // M7 Slice 3b (Autonomy: scheduling/triggers) — Slice 6 is merged on this
        // branch, so `run_tool_script` is wired to the REAL `executionRouter`
        // (never nil): a script always routes through the sandbox backend the
        // router resolves for `.subagent`, never falls back to host.
        agentTools.append(ScriptedBatchTool(executionRouter: executionRouter))

        let agentToolRegistry = AgentToolRegistry(
            tools: agentTools,
            dynamicTools: { [weak mcpServerRegistry] in mcpServerRegistry?.currentTools() ?? [] })

        // M7 Slice 3b Task 21 — every `RunManager`-driven headless run (background,
        // AND schedule/event runs, which enqueue through the SAME `RunManager` /
        // `BackgroundRunRunner` — see the residual-gap note below) is sandboxed at
        // trust tier `.background`: its own tool registry swaps in a `.background`-
        // tier `RunTerminalTool` (the shared `agentToolRegistry`'s instance is fixed
        // at `.mainInteractive`, the only tier ever eligible for `HostBackend`), and
        // its `AgentSession` gets a non-nil `sandboxAllowList` so the compose layer
        // (`SandboxPermissionPolicy.compose`) is always active.
        //
        // RESIDUAL GAP CLOSED (M7 Wave B): `AgentRun.posture` now carries the
        // originating schedule/trigger's `SavedExecutionPosture` end-to-end —
        // `RunManager.enqueue(posture:)` → `AgentRunRunner.execute(posture:)` →
        // `BackgroundRunRunner`'s `makeSession(posture:)` below, which projects
        // `posture.sandboxProfileID` into `ExecutionRouter.resolveProfile` and
        // `posture.permissionMode` into `AgentSession`'s narrowing-only
        // `permissionModeOverride`. A `nil` posture (plain `.chat` runs) or an
        // unresolvable `sandboxProfileID` falls back to the SAME `.background`-
        // tier default as before — fail-closed, never `.host`, never escalation.
        // `canvas_render` is EXCLUDED from the background/headless tool list: it's
        // bound to the foreground `canvasStore` (sessionKey "default", the SAME
        // store the `CanvasApp` pane reads), so an autonomous background/schedule/
        // trigger run calling it would silently mutate the canvas the user is
        // looking at — a cross-session split-brain. The foreground
        // `agentToolRegistry` above keeps `canvas_render`; only this background
        // copy drops it.
        var backgroundAgentTools = agentTools.filter { !($0 is CanvasRenderTool) }
        if let idx = backgroundAgentTools.firstIndex(where: { $0.name == "run_terminal" }) {
            backgroundAgentTools[idx] = RunTerminalTool(
                actionHub: agentActionHub, router: executionRouter, trustTier: .background)
        }
        let backgroundToolRegistry = AgentToolRegistry(
            tools: backgroundAgentTools,
            dynamicTools: { [weak mcpServerRegistry] in mcpServerRegistry?.currentTools() ?? [] })
        let runNotifier = UserNotificationRunNotifier()
        let runManager = RunManager(
            persistence: persistence,
            runner: BackgroundRunRunner(makeSession: { posture in
                // M7 Wave B: resolve THIS run's own sandbox profile from its
                // posture (nil sandboxProfileID == nil policy's behavior below,
                // so a `.chat`/postureless run resolves identically to before).
                let policy = AgentExecutionPolicy(
                    sandboxProfileID: posture?.sandboxProfileID, allowCloud: false, toolAllowList: nil)
                let sandboxProfile = executionRouter.resolveProfile(tier: .background, policy: policy)
                // Narrowing-only: an unrecognized `permissionMode` string (future/
                // corrupt payload) degrades to `nil` (no override) rather than
                // guessing — `AgentSession.effectiveMode()` then simply falls back
                // to the workspace's own mode, never a wider or crashing path.
                let permissionModeOverride = posture.flatMap { AgentPermissionMode(rawValue: $0.permissionMode) }
                return AgentSession(
                    providerFor: providerFor, connections: connectionStore, config: agentConfigStore,
                    context: agentContextService, registry: backgroundToolRegistry, permissions: agentPermissionStore,
                    agents: agentStore, editJournal: editJournal, unattended: true,
                    sandboxAllowList: sandboxProfile.toolAllowList, agentAllowList: nil,
                    router: modelRouter, usage: usageTracker, runtime: runtimeOptionsStore,
                    commands: commandRegistry, authProfiles: authProfileStore,
                    candidatesProvider: candidatesProvider,
                    isLocalConnection: { [localModelProbe] connection in localModelProbe.isLocal(connection) },
                    permissionModeOverride: permissionModeOverride)
            }),
            notifier: runNotifier, maxConcurrent: 2)

        // M7 Slice 7: menu-bar presence wraps the SAME `runManager` above via
        // `RunManagerMenuBarAdapter`, so the status-item popover's run list is
        // always in lockstep with the Runs surface and any background trigger.
        let menuBarPresence = MenuBarPresence(runs: RunManagerMenuBarAdapter(manager: runManager))

        // M7 Slice 3b (Autonomy: scheduling/triggers) — the whole subsystem live:
        // `scheduleStore` persists `AgentSchedule`s (`ScheduleUIView`'s create/edit
        // list); `scheduleRunner` fires enabled `.time` schedules on a 60s tick;
        // `triggerDispatcher` fans event triggers (file/git change, webhook) into
        // `runManager`, rate-limited; `fileChangeWatcher` is registered below for
        // every enabled `.fileChange`/`.gitChange` schedule found at launch. A
        // schedule added/enabled later (via `ScheduleUIView`) only starts firing
        // its FSEvents watch on the NEXT launch — this loop is a one-time seed,
        // matching `WorkspaceFileIndex`'s launch-time-only refresh above.
        let scheduleStore = ScheduleStore(persistence: persistence)
        let triggerDispatcher = TriggerDispatcher(store: scheduleStore, runs: runManager)
        let scheduleRunner = ScheduleRunner(store: scheduleStore, runs: runManager)
        let fileChangeWatcher = FileChangeWatcher()
        for schedule in scheduleStore.schedules where schedule.enabled {
            switch schedule.trigger {
            case .fileChange(let path, let glob):
                fileChangeWatcher.watch(scheduleID: schedule.id, path: path, glob: glob) { event in
                    triggerDispatcher.fire(event)
                }
            case .gitChange(let repoPath):
                // PROVISIONAL: prefer a native Git Mage change event if/when one
                // exists; until then, watch `.git` refs via FSEvents.
                fileChangeWatcher.watchGitChange(scheduleID: schedule.id, repoPath: repoPath) { event in
                    triggerDispatcher.fire(event)
                }
            case .time, .webhook:
                break   // .time fires via scheduleRunner; .webhook via WebhookServer (off by default)
            case .unknown:
                break   // forward-compat (M7 Wave B): a future trigger kind this build doesn't know yet
            }
        }
        scheduleRunner.start()
        // `WebhookServer` is deliberately NOT constructed here: it needs a port +
        // bearer token (from `SecretStore`, once the user enables it in a future
        // settings surface) and must never `start()` at launch — constructing it
        // eagerly with a placeholder token would be a live, unauthenticated-by-
        // default local listener. Left for the settings surface that turns it on.

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

        let voiceService = VoiceService(persistence: persistence, connections: connectionStore)
        voiceService.attachSession(agentSession)

        return (
            subagentCoordinator, runManager, scheduleStore, scheduleRunner, triggerDispatcher, fileChangeWatcher,
            assistantWorkingDirectory, workspaceFileIndex, agentSession, voiceService, menuBarPresence
        )
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
    ) -> @MainActor (AgentProfile, AgentToolRegistry, String, Set<String>) -> AgentSession {
        { profile, registry, model, sandboxAllowList in
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
                // M7 Slice 3b Task 21: every child session is sandboxed at trust
                // tier `.subagent` — `sandboxAllowList` is always non-nil here (the
                // runner resolves it per-run via `ExecutionRouter.resolveProfile`),
                // so the compose layer is always active for a spawned subagent.
                // `agentAllowList: nil` — see Task 21 report: `AgentToolPolicy`'s
                // `.restricted` case (deny-list + tool-class allow) doesn't reduce
                // losslessly to `compose`'s `Set<String>?` allow-only shape, and the
                // full policy is already enforced by `SubagentRegistryFilter` (the
                // child's registry never even contains a disallowed tool) — a lossy
                // second projection here would risk incorrectly denying a call the
                // class-based allow already permits.
                unattended: true,
                sandboxAllowList: sandboxAllowList,
                agentAllowList: nil,
                runtime: pinned)
        }
    }
}
