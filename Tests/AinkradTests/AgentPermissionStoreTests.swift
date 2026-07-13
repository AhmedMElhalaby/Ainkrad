import Foundation
import Testing
@testable import Ainkrad

@Suite("AgentPermissionStore")
@MainActor
struct AgentPermissionStoreTests {
    @Test func defaultsToAsk() {
        let ws = UUID()
        let store = AgentPermissionStore(persistence: InMemoryPersistenceStore(), currentWorkspaceID: { ws })
        #expect(store.mode == .ask)
    }

    @Test func setModePersistsPerWorkspace() {
        let wsA = UUID(); let wsB = UUID()
        var active = wsA
        let persistence = InMemoryPersistenceStore()
        let store = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { active })
        store.setMode(.fullAuto)
        #expect(store.mode == .fullAuto)
        active = wsB
        #expect(store.mode == .ask)   // other workspace unaffected

        // Reload from the same persistence: workspace A's mode survives.
        active = wsA
        let reloaded = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { active })
        #expect(reloaded.mode == .fullAuto)
    }
}
