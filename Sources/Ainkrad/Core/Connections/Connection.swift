import Foundation

/// A third-party service Ainkrad can authenticate against. The foundation for
/// the future settings surface (Claude / OpenAI auth); more providers later.
enum ConnectionProvider: String, Codable, CaseIterable, Equatable {
    case claude
    case openai
}

/// A configured connection. The secret (API token) is NOT stored here — it
/// lives in the Keychain under `secretID`. Only non-secret metadata persists.
struct Connection: Codable, Equatable, Identifiable {
    let id: UUID
    var provider: ConnectionProvider
    var displayName: String
    var createdAt: Date

    /// Keychain id for this connection's token.
    var secretID: String { "connection.\(id.uuidString)" }
}

/// Persisted, non-secret list of connections.
struct ConnectionsDocument: PersistableDocument {
    static let documentID = "connections"
    var connections: [Connection] = []
}
