import Foundation
import AinkradAppKit
import AinkradHostRuntime

/// `AppEnvironment.bootstrap(rootURL:defaults:)` split into cohesive helpers
/// (M7 finalize Wave D, D2) — this file holds the next two sequential
/// blocks: the sandbox/execution router + the host-facing agent tools, then
/// the Model Router / Usage / Failover wiring (M7 Slice 5b). Pure
/// value-construction, mirroring `bootstrap()`'s original order exactly.
extension AppEnvironment {
    /// Third block of `bootstrap()`: M7 Slice 6 (Security & Sandboxing) —
    /// every execution backend registered by kind, plus the base agent tool
    /// set (read/edit/workspace/terminal/git, memory tools if available,
    /// skill tools, MCP registry, and the Live Canvas render tool).
    static func bootstrapExecutionAndTools(
        persistence: PersistenceStore,
        secrets: SecretStore,
        lspServerRegistry: LSPServerRegistry,
        editJournal: EditJournal,
        workspaceManager: WorkspaceManager,
        agentActionHub: AgentActionRegistryHub,
        agentContextHub: AgentContextRegistryHub,
        memoryService: MemoryService?,
        mcpConfigStore: MCPServerConfigStore,
        skillRegistry: SkillRegistry
    ) -> (
        sandboxProfileStore: SandboxProfileStore,
        cloudCredentialsStore: CloudCredentialsStore,
        executionRouter: ExecutionRouter,
        agentTools: [any AgentTool],
        mcpServerRegistry: MCPServerRegistry,
        canvasStore: CanvasStore
    ) {
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

        // M7 Slice 7 (Live Canvas): `canvas_render` only draws structured cards
        // from agent-supplied data — it executes nothing and touches no files
        // or system state (see `CanvasRenderTool`), so it's appended alongside
        // the other read-class tools. `canvasStore` defaults to sessionKey
        // "default" (PROVISIONAL — per-session keying awaits a stable session
        // identifier from Slice 5; see Task 12 brief).
        let canvasStore = CanvasStore(persistence: persistence)
        agentTools.append(CanvasRenderTool(store: canvasStore))

        return (sandboxProfileStore, cloudCredentialsStore, executionRouter, agentTools, mcpServerRegistry, canvasStore)
    }

    /// Fourth block of `bootstrap()`: Model Router / Usage / Failover
    /// wiring (M7 Slice 5b) — the model catalog, price table, usage tracker,
    /// router, local-model reachability probe/cache, auth profiles, the
    /// router `candidatesProvider` closure, and the command registry
    /// (builtins + `/stop`).
    static func bootstrapModelRouting(
        persistence: PersistenceStore,
        secrets: SecretStore,
        connectionStore: ConnectionStore,
        discoveredModelsStore: DiscoveredModelsStore
    ) -> (
        modelCatalogService: ModelCatalogService,
        agentStore: AgentStore,
        modelCatalog: ModelCatalog,
        modelPriceTable: ModelPriceTable,
        routerOutcomeStore: RouterOutcomeStore,
        modelRouter: ModelRouter,
        usageTracker: UsageTracker,
        runtimeOptionsStore: RuntimeOptionsStore,
        localModelProbe: LocalModelProbe,
        localModelAvailability: LocalModelAvailability,
        authProfileStore: AuthProfileStore,
        candidatesProvider: @MainActor () -> [RouterCandidate],
        commandRegistry: CommandRegistry
    ) {
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
        let candidatesProvider: @MainActor () -> [RouterCandidate] = { [connectionStore, modelCatalog, localModelProbe, localModelAvailability, discoveredModelsStore] in
            let all = connectionStore.connections.flatMap { connection -> [RouterCandidate] in
                // Prefer the connection's LIVE-discovered models; fall back to the
                // preset's curated list only when nothing was ever discovered. This
                // is what lets the Auto router pick a real provider model rather than
                // a hardcoded curated one.
                let models = discoveredModelsStore.models(for: connection.id)
                    ?? ProviderPreset.preset(id: connection.presetID).curatedModels
                return models.map { modelID in
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
            name: "stop", summary: "Interrupt the current turn", usage: "/stop", category: .session) { _, session in
            session.interrupt()
            return .handled(note: "Interrupted.")
        })

        return (
            modelCatalogService, agentStore, modelCatalog, modelPriceTable, routerOutcomeStore, modelRouter,
            usageTracker, runtimeOptionsStore, localModelProbe, localModelAvailability, authProfileStore,
            candidatesProvider, commandRegistry
        )
    }
}
