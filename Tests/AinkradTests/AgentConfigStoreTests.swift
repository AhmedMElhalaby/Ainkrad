import Testing
import Foundation
@testable import Ainkrad

@Suite("AgentConfigStore")
struct AgentConfigStoreTests {
    @MainActor private func makeStore(_ persistence: PersistenceStore) -> AgentConfigStore {
        AgentConfigStore(persistence: persistence)
    }

    @Test("starts with the documented defaults")
    @MainActor func startsWithDefaults() {
        let store = makeStore(InMemoryPersistenceStore())
        #expect(store.current == AgentModelConfig(provider: .claude, model: "claude-opus-4-8", effort: "xhigh"))
    }

    @Test("mutating provider/model survives a fresh store over the same persistence")
    @MainActor func roundTrips() {
        let persistence = InMemoryPersistenceStore()
        let first = makeStore(persistence)
        first.setProvider(.openai)
        first.setModel("gpt-5")

        let second = makeStore(persistence)
        #expect(second.current == AgentModelConfig(provider: .openai, model: "gpt-5", effort: "xhigh"))
    }

    @Test("setEffort persists independently of provider/model")
    @MainActor func setEffortPersists() {
        let persistence = InMemoryPersistenceStore()
        let first = makeStore(persistence)
        first.setEffort("low")

        let second = makeStore(persistence)
        #expect(second.current.effort == "low")
    }
}
