import Observation
import Foundation

/// Owns the list of `Connection`s and mediates their secrets. Metadata is
/// persisted as a document; tokens go to the `SecretStore` (Keychain) only.
@MainActor
@Observable
final class ConnectionStore {
    private(set) var connections: [Connection]
    private let persistence: PersistenceStore
    private let secrets: SecretStore

    init(persistence: PersistenceStore, secrets: SecretStore) {
        self.persistence = persistence
        self.secrets = secrets
        self.connections = persistence.load(ConnectionsDocument.self)?.connections ?? []
    }

    @discardableResult
    func addConnection(provider: ConnectionProvider, displayName: String, token: String) -> Connection {
        let connection = Connection(
            id: UUID(), provider: provider, displayName: displayName, createdAt: Date())
        secrets.setSecret(token, for: connection.secretID)
        connections.append(connection)
        persist()
        return connection
    }

    func token(for connection: Connection) -> String? {
        secrets.secret(for: connection.secretID)
    }

    func updateToken(_ token: String, for connection: Connection) {
        secrets.setSecret(token, for: connection.secretID)
    }

    func removeConnection(_ connection: Connection) {
        secrets.setSecret(nil, for: connection.secretID)
        connections.removeAll { $0.id == connection.id }
        persist()
    }

    private func persist() {
        persistence.save(ConnectionsDocument(connections: connections))
    }
}
