// Tests/AinkradTests/Support/TestSessionFactory.swift
//
// Shared AgentSession test harness, mirroring the file-private `makeSession`
// factory in AgentSessionToolLoopTests.swift, extended with an `agents:`
// parameter so Task 4's agent-policy composition can be exercised without
// duplicating the wiring boilerplate in every test file. Task 16 further
// extends it with the Model Router / Usage / Failover wiring params, plus
// `resolveWithPin`/`resolveTrivialNoPin` helpers for the model-resolution tests.
import Foundation
@testable import Ainkrad

@MainActor
private final class NoopProvider: LLMProvider {
    func send(messages: [AgentMessage], system: String, tools: [AgentToolSchema],
              model: AgentModelConfig, apiKey: String) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// A fake write-classified tool, standing in for `EditFileTool` in tests that
/// only need `name`/`permission` (never actually mutates anything).
@MainActor
struct FakeEditFileTool: AgentTool {
    let name = "edit_file"
    let description = "edits a file"
    var parametersSchema: JSONValue { .object(["type": .string("object")]) }
    let permission: ToolPermissionClass = .write
    func execute(_ input: JSONValue) async throws -> ToolResult { ToolResult(content: "edited", isError: false) }
}

/// A fake read-classified tool, so Plan-agent schema filtering has something
/// it is still allowed to see.
@MainActor
struct FakeReadFileTool: AgentTool {
    let name = "read_file"
    let description = "reads a file"
    var parametersSchema: JSONValue { .object(["type": .string("object")]) }
    let permission: ToolPermissionClass = .read
    func execute(_ input: JSONValue) async throws -> ToolResult { ToolResult(content: "read", isError: false) }
}

/// A scripted `LLMProvider` double used by the model-resolution tests: replays a
/// fixed event script and records the `AgentModelConfig`/`apiKey` it was called with,
/// so a test can assert exactly which resolved model actually reached the provider.
@MainActor
final class RecordingProvider: LLMProvider {
    private(set) var lastModel: AgentModelConfig?
    private(set) var lastApiKey: String?
    private(set) var callCount = 0
    private let script: [AgentEvent]
    init(script: [AgentEvent]) { self.script = script }

    func send(messages: [AgentMessage], system: String, tools: [AgentToolSchema],
              model: AgentModelConfig, apiKey: String) -> AsyncThrowingStream<AgentEvent, Error> {
        callCount += 1
        lastModel = model
        lastApiKey = apiKey
        let events = script
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// A minimal `AgentSession` builder for tests that stand in for a spawned
/// subagent's child session (e.g. `AgentSessionSubagentRunnerTests`): the
/// returned session is wired to a `RecordingProvider` that replays a single
/// `finalText` assistant turn, so calling `send(_:)` on it settles with the
/// transcript ending in an assistant message equal to `finalText`.
@MainActor
enum StubChildSession {
    static func make(finalText: String) -> AgentSession {
        let persistence = InMemoryPersistenceStore()
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        _ = connections.addConnection(preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
                                      baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        let config = AgentConfigStore(persistence: persistence)
        let context = AgentContextService(hub: AgentContextRegistryHub(),
                                          settings: AgentContextSettingsStore(persistence: persistence))
        let permissions = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() })
        let provider = RecordingProvider(script: [.textDelta(finalText), .done(stopReason: "end_turn")])
        return AgentSession(
            providerFor: { _ in provider },
            connections: connections, config: config, context: context,
            registry: AgentToolRegistry(tools: []), permissions: permissions)
    }
}

/// A minimal `AgentSession` that settles into `.failed` on the first `send`,
/// via the same "no connection configured" path `AgentSession` already uses
/// (no `Connection` registered in its `ConnectionStore`). Stands in for a
/// spawned subagent's child session in tests that assert failure isolation.
@MainActor
enum FailingChildSession {
    static func make() -> AgentSession {
        let persistence = InMemoryPersistenceStore()
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        let config = AgentConfigStore(persistence: persistence)
        let context = AgentContextService(hub: AgentContextRegistryHub(),
                                          settings: AgentContextSettingsStore(persistence: persistence))
        let permissions = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() })
        return AgentSession(
            providerFor: { _ in RecordingProvider(script: []) },
            connections: connections, config: config, context: context,
            registry: AgentToolRegistry(tools: []), permissions: permissions)
    }
}

@MainActor
enum TestSessionFactory {
    /// Builds a fully-wired `AgentSession` backed by an in-memory persistence
    /// stack and a `NoopProvider` (tests here drive `execute`/`allowedSchemas`/
    /// `effectiveMode` directly and never call `send`). Pass `connections`/
    /// `persistence` when a test needs a handle on the connection actually wired
    /// in (e.g. to build `RouterCandidate`s that share its `connectionID`).
    static func make(
        agents: AgentStore? = nil,
        mode: AgentPermissionMode = .ask,
        gateReads: Bool = true,
        memory: MemoryService? = nil,
        configModel: String = "claude-opus-4-8",
        connections: ConnectionStore? = nil,
        persistence: PersistenceStore? = nil,
        router: ModelRouter? = nil,
        usage: UsageTracker? = nil,
        runtime: RuntimeOptionsStore? = nil,
        commands: CommandRegistry? = nil,
        candidatesProvider: (@MainActor () -> [RouterCandidate])? = nil
    ) -> AgentSession {
        let persistence = persistence ?? InMemoryPersistenceStore()
        let ws = UUID()
        let permissions = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { ws })
        permissions.setMode(mode)
        permissions.setGateReads(gateReads)
        let resolvedConnections: ConnectionStore
        if let connections {
            resolvedConnections = connections
        } else {
            resolvedConnections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
            _ = resolvedConnections.addConnection(preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
                                                  baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        }
        let config = AgentConfigStore(persistence: persistence)
        config.setModel(configModel)
        let context = AgentContextService(hub: AgentContextRegistryHub(),
                                          settings: AgentContextSettingsStore(persistence: persistence))
        let registry = AgentToolRegistry(tools: [FakeEditFileTool(), FakeReadFileTool()])
        return AgentSession(
            providerFor: { _ in NoopProvider() },
            connections: resolvedConnections, config: config, context: context,
            registry: registry, permissions: permissions, memory: memory, agents: agents,
            router: router, usage: usage, runtime: runtime, commands: commands,
            candidatesProvider: candidatesProvider)
    }

    /// A local (free) and a premium candidate on the given connection, for the
    /// model-resolution tests.
    private static func localAndPremiumCandidates(connectionID: UUID) -> [RouterCandidate] {
        [
            RouterCandidate(connectionID: connectionID, model: "qwen2.5-coder",
                descriptor: ModelDescriptor(id: "qwen2.5-coder", tier: .local, contextWindow: 32_000,
                                            capabilities: [.toolUse], matchPrefixes: ["qwen"])),
            RouterCandidate(connectionID: connectionID, model: "claude-opus-4-8",
                descriptor: ModelDescriptor(id: "claude-opus-4-8", tier: .premium, contextWindow: 200_000,
                                            capabilities: [.vision, .toolUse, .reasoningEffort], matchPrefixes: ["claude-opus"])),
        ]
    }

    /// A session wired with a router + local/premium candidates + a runtime pin to
    /// `pinnedModel`. Exercises invariant 1 (a session-level pin always overrides the
    /// router's auto-pick, even though the router itself would free-first to local).
    static func resolveWithPin(_ pinnedModel: String) async -> AgentSession.ResolvedTurn {
        let persistence = InMemoryPersistenceStore()
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        let connection = connections.addConnection(preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
                                                   baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        let runtime = RuntimeOptionsStore(persistence: persistence)
        runtime.pinModel(pinnedModel)
        let router = ModelRouter(catalog: ModelCatalog(), policy: .saveMoney,
                                 outcomes: RouterOutcomeStore(persistence: persistence))
        let candidates = localAndPremiumCandidates(connectionID: connection.id)
        let session = make(connections: connections, persistence: persistence,
                           router: router, runtime: runtime, candidatesProvider: { candidates })
        return await session.resolveTurnForTesting()
    }

    /// A session wired with a router + local/premium candidates and NO pin. Exercises
    /// "router picks free-first (local) when nothing overrides it".
    static func resolveTrivialNoPin() async -> AgentSession.ResolvedTurn {
        let persistence = InMemoryPersistenceStore()
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        let connection = connections.addConnection(preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
                                                   baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        let runtime = RuntimeOptionsStore(persistence: persistence)
        let router = ModelRouter(catalog: ModelCatalog(), policy: .saveMoney,
                                 outcomes: RouterOutcomeStore(persistence: persistence))
        let candidates = localAndPremiumCandidates(connectionID: connection.id)
        let session = make(connections: connections, persistence: persistence,
                           router: router, runtime: runtime, candidatesProvider: { candidates })
        return await session.resolveTurnForTesting()
    }
}
