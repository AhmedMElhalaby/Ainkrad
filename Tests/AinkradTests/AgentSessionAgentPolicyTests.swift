// Tests/AinkradTests/AgentSessionAgentPolicyTests.swift
import Foundation
import Testing
@testable import Ainkrad

@Suite("AgentSession agent policy")
@MainActor
struct AgentSessionAgentPolicyTests {
    @Test func planAgentBlocksWriteToolBeforeGate() async throws {
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        agents.setActive(BuiltInAgents.planID)
        let session = TestSessionFactory.make(agents: agents)
        let result = await session.executeForTesting(
            ToolCall(id: "1", name: "edit_file", input: .object(["path": .string("/tmp/x")])))
        #expect(result.isError)
        #expect(result.content.contains("not permitted"))
    }

    @Test func buildAgentAllowsWriteToolThroughToGate() async throws {
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        agents.setActive(BuiltInAgents.buildID)
        let session = TestSessionFactory.make(agents: agents)
        // Build permits the tool; it is then visible in the schemas presented
        // to the provider (rather than being filtered out pre-gate like Plan).
        let schemas = session.allowedSchemasForTesting()
        #expect(schemas.contains { $0.name == "edit_file" })
    }

    @Test func planAgentSchemasExcludeWriteTool() async throws {
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        agents.setActive(BuiltInAgents.planID)
        let session = TestSessionFactory.make(agents: agents)
        // edit_file is present in the full registry (see buildAgentAllowsWriteToolThroughToGate),
        // so a non-empty absence here proves filtering, not an empty registry.
        let schemas = session.allowedSchemasForTesting()
        #expect(!schemas.contains { $0.name == "edit_file" })
    }

    @Test func postureComposesMostRestrictiveWins() {
        // Workspace fullAuto + a custom agent with posture .ask → effective .ask.
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        var reviewer = AgentProfile.custom(name: "Reviewer", instructions: "x")
        reviewer.permissionPosture = .ask
        agents.setActive(agents.add(reviewer).id)
        let session = TestSessionFactory.make(agents: agents, mode: .fullAuto)
        #expect(session.effectiveModeForTesting() == .ask)
    }
}
