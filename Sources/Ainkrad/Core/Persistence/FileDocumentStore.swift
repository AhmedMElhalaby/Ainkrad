import Foundation

/// A `PersistenceStore` that writes each document as a versioned JSON envelope
/// to `<rootURL>/<documentID>.json`. Writes are atomic (temp file + rename).
/// A file that fails to decode is quarantined (renamed aside) and treated as
/// absent, so a single corrupt document can never crash launch or block the
/// rest of persistence. A write-through cache serves repeat reads.
final class FileDocumentStore: PersistenceStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private var cache: [String: any PersistableDocument] = [:]

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    /// `~/Library/Application Support/<bundle-id>/Documents`.
    static func defaultDocumentsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// Drops the in-memory cache. Call after files are written out of band
    /// (e.g. after an import) so subsequent loads read fresh from disk.
    func clearCache() { cache.removeAll() }

    private func fileURL(for id: String) -> URL {
        rootURL.appendingPathComponent("\(id).json")
    }

    private struct SaveEnvelope<Payload: Codable>: Codable {
        let schemaVersion: Int
        let updatedAt: Date
        let payload: Payload
    }

    private struct RawEnvelope: Codable {
        let schemaVersion: Int
        let updatedAt: Date?
        let payload: JSONValue
    }

    func load<T: PersistableDocument>(_ type: T.Type) -> T? {
        if let cached = cache[T.documentID] as? T { return cached }
        let url = fileURL(for: T.documentID)
        guard let data = try? Data(contentsOf: url) else { return nil }

        guard let raw = try? PersistenceCoding.decoder.decode(RawEnvelope.self, from: data) else {
            quarantine(url)
            return nil
        }
        // Task 4 replaces the version check below with the migrator chain.
        guard raw.schemaVersion == T.currentSchemaVersion else {
            quarantine(url)
            return nil
        }
        guard let payloadData = try? PersistenceCoding.encoder.encode(raw.payload),
              let value = try? PersistenceCoding.decoder.decode(T.self, from: payloadData) else {
            quarantine(url)
            return nil
        }
        cache[T.documentID] = value
        return value
    }

    func save<T: PersistableDocument>(_ document: T) {
        let envelope = SaveEnvelope(
            schemaVersion: T.currentSchemaVersion, updatedAt: Date(), payload: document)
        guard let data = try? PersistenceCoding.encoder.encode(envelope) else {
            Log.persistence.error("Failed to encode \(T.documentID, privacy: .public)")
            return
        }
        do {
            try data.write(to: fileURL(for: T.documentID), options: .atomic)
            cache[T.documentID] = document
        } catch {
            Log.persistence.error("Failed to write \(T.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete<T: PersistableDocument>(_ type: T.Type) {
        cache[T.documentID] = nil
        try? fileManager.removeItem(at: fileURL(for: T.documentID))
    }

    /// Renames a bad file aside so it is out of the way but recoverable.
    private func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = url.appendingPathExtension("corrupt-\(stamp)")
        try? fileManager.moveItem(at: url, to: destination)
        Log.persistence.error("Quarantined corrupt document \(url.lastPathComponent, privacy: .public)")
    }
}
