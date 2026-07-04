import Testing
import Foundation
@testable import Ainkrad

@Suite("ConnectionStore")
final class ConnectionStoreTests {
    let persistence = InMemoryPersistenceStore()
    let secrets = InMemorySecretStore()

    @MainActor private func makeStore() -> ConnectionStore {
        ConnectionStore(persistence: persistence, secrets: secrets)
    }

    @Test("starts empty")
    @MainActor func startsEmpty() {
        #expect(makeStore().connections.isEmpty)
    }

    @Test("adding a connection stores metadata as a document and the token in secrets")
    @MainActor func addStoresMetadataAndSecret() {
        let store = makeStore()
        let connection = store.addConnection(provider: .claude, displayName: "Work", token: "sk-abc")

        #expect(store.connections.map(\.id) == [connection.id])
        #expect(store.token(for: connection) == "sk-abc")
        // Token must NOT be in the persisted document.
        let doc = persistence.load(ConnectionsDocument.self)
        #expect(doc?.connections.count == 1)
        #expect(doc?.connections.first?.displayName == "Work")
    }

    @Test("connections survive a fresh store (metadata reloads; secret stays in keychain)")
    @MainActor func survivesReload() {
        let first = makeStore()
        let connection = first.addConnection(provider: .openai, displayName: "Personal", token: "sk-xyz")

        let second = makeStore()
        #expect(second.connections.map(\.id) == [connection.id])
        #expect(second.token(for: connection) == "sk-xyz")
    }

    @Test("removing a connection clears its metadata and secret")
    @MainActor func removeClearsBoth() {
        let store = makeStore()
        let connection = store.addConnection(provider: .claude, displayName: "X", token: "t")
        store.removeConnection(connection)

        #expect(store.connections.isEmpty)
        #expect(store.token(for: connection) == nil)
        #expect(persistence.load(ConnectionsDocument.self)?.connections.isEmpty == true)
    }
}
