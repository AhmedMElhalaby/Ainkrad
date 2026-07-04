import Foundation

/// A `PersistenceStore` kept entirely in memory. Encodes each document to
/// `Data` on save (so it exercises the same `Codable` path as disk) and decodes
/// on load. Migration is not exercised in memory — stored payloads are always
/// at the current version. Primarily for tests, and usable as a null store.
final class InMemoryPersistenceStore: PersistenceStore {
    private var storage: [String: Data] = [:]

    func load<T: PersistableDocument>(_ type: T.Type) -> T? {
        guard let data = storage[T.documentID] else { return nil }
        return try? PersistenceCoding.decoder.decode(T.self, from: data)
    }

    func save<T: PersistableDocument>(_ document: T) {
        guard let data = try? PersistenceCoding.encoder.encode(document) else { return }
        storage[T.documentID] = data
    }

    func delete<T: PersistableDocument>(_ type: T.Type) {
        storage[T.documentID] = nil
    }
}
