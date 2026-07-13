import Testing
import Foundation
@testable import Ainkrad

/// Validates the `ConnectionStore` interaction the Assistant Connections
/// settings UI performs (add / reveal / remove a provider API key). The
/// SwiftUI layer itself is verified later by screenshot (Task B10/B11).
@Suite("Assistant Connections")
@MainActor
struct AssistantConnectionsTests {
    private func makeStore() -> ConnectionStore {
        ConnectionStore(persistence: InMemoryPersistenceStore(), secrets: InMemorySecretStore())
    }

    @Test("adding a Claude key persists a Connection and the token under its secretID")
    func addingPersistsConnectionAndSecret() {
        let store = makeStore()

        let connection = store.addConnection(provider: .claude, displayName: "Claude Key", token: "sk-ant-123")

        #expect(connection.provider == .claude)
        #expect(store.connections.map(\.id) == [connection.id])
        #expect(store.token(for: connection) == "sk-ant-123")
    }

    @Test("token(for:) returns the persisted token")
    func tokenForReturnsPersistedToken() {
        let store = makeStore()
        let connection = store.addConnection(provider: .openai, displayName: "OpenAI Key", token: "sk-oai-456")

        #expect(store.token(for: connection) == "sk-oai-456")
    }

    @Test("removeConnection clears both the metadata and the secret")
    func removeClearsMetadataAndSecret() {
        let store = makeStore()
        let connection = store.addConnection(provider: .claude, displayName: "Claude Key", token: "sk-ant-789")

        store.removeConnection(connection)

        #expect(store.connections.isEmpty)
        #expect(store.token(for: connection) == nil)
    }
}
