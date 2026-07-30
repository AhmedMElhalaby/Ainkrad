import Foundation
import Testing
@testable import Ainkrad

@Suite("Setup assistant step")
@MainActor
struct SetupAssistantStepTests {
    @Test func choosingABuiltInAgentMakesItActive() {
        let t = TestHome.make("agent")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupAssistant.apply(profile: BuiltInAgents.plan, model: "claude-opus-4-8",
                             effort: "xhigh", agents: env.agentStore, config: env.agentConfigStore)

        #expect(env.agentStore.active.id == BuiltInAgents.plan.id)
        #expect(env.agentConfigStore.current.model == "claude-opus-4-8")
    }

    @Test func acustomPersonaIsAddedThenActivated() {
        let t = TestHome.make("agent2")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let custom = AgentProfile.custom(name: "Scribe", instructions: "Be terse.")
        SetupAssistant.apply(profile: custom, model: "claude-opus-4-8",
                             effort: "high", agents: env.agentStore, config: env.agentConfigStore)

        #expect(env.agentStore.active.name == "Scribe")
        #expect(env.agentConfigStore.current.effort == "high")
    }
}
