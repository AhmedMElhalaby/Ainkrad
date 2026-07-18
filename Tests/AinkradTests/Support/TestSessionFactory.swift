// Tests/AinkradTests/Support/TestSessionFactory.swift
//
// Shared AgentSession test harness, mirroring the file-private `makeSession`
// factory in AgentSessionToolLoopTests.swift, extended with an `agents:`
// parameter so Task 4's agent-policy composition can be exercised without
// duplicating the wiring boilerplate in every test file.
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

@MainActor
enum TestSessionFactory {
    /// Builds a fully-wired `AgentSession` backed by an in-memory persistence
    /// stack and a `NoopProvider` (tests here drive `execute`/`allowedSchemas`/
    /// `effectiveMode` directly and never call `send`).
    static func make(
        agents: AgentStore? = nil,
        mode: AgentPermissionMode = .ask,
        gateReads: Bool = true
    ) -> AgentSession {
        let persistence = InMemoryPersistenceStore()
        let ws = UUID()
        let permissions = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { ws })
        permissions.setMode(mode)
        permissions.setGateReads(gateReads)
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        _ = connections.addConnection(preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
                                      baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        let config = AgentConfigStore(persistence: persistence)
        let context = AgentContextService(hub: AgentContextRegistryHub(),
                                          settings: AgentContextSettingsStore(persistence: persistence))
        let registry = AgentToolRegistry(tools: [FakeEditFileTool(), FakeReadFileTool()])
        return AgentSession(
            providerFor: { _ in NoopProvider() },
            connections: connections, config: config, context: context,
            registry: registry, permissions: permissions, agents: agents)
    }
}
