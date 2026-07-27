import Foundation
import Observation
import AinkradHostRuntime

/// Metadata for one on-disk share artifact. The HTML always lives at the
/// deterministic path `<baseDirectory>/<id>/index.html`, so the absolute
/// `filePath` is RECOMPUTED from the store's current base directory + `id` on
/// every load (see `SessionShareStore.init`) — a persisted stale path can never
/// be trusted, which keeps records valid across an Application-Support path
/// change (bundle rename, sandbox relocation).
struct SharedSessionRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var createdAt: Date
    /// Absolute path to the artifact, resolved against the store's base directory
    /// at load time from `id`. Persisted for convenience but never authoritative.
    var filePath: String
    var fileURL: URL { URL(fileURLWithPath: filePath) }
}

struct SharedSessionsDocument: PersistableDocument {
    static let documentID = "assistant-shares"
    var records: [SharedSessionRecord] = []
    init(records: [SharedSessionRecord] = []) { self.records = records }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent([SharedSessionRecord].self, forKey: .records) ?? []
    }
}

/// Writes self-contained HTML share artifacts to disk and tracks their
/// metadata. Private-by-default: only writes on explicit `share(...)`.
@MainActor
@Observable
final class SessionShareStore {
    private(set) var shares: [SharedSessionRecord] = []
    private let persistence: PersistenceStore
    private let baseDirectory: URL
    private let now: () -> Date

    /// `baseDirectory` defaults to `~/Library/Application Support/<bundle>/Shares`
    /// (same base as `MemoryPaths.defaultRoot()`); tests inject a temp dir.
    init(persistence: PersistenceStore,
         baseDirectory: URL = SessionShareStore.defaultDirectory(),
         now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.baseDirectory = baseDirectory
        self.now = now
        // Recompute every record's absolute path from the CURRENT base directory +
        // id, so a persisted path from a prior (possibly relocated) base is never
        // trusted — the artifact's location is fully determined by its id.
        let loaded = (persistence.load(SharedSessionsDocument.self) ?? SharedSessionsDocument()).records
        shares = loaded.map { record in
            var r = record
            r.filePath = SessionShareStore.artifactURL(base: baseDirectory, id: record.id).path
            return r
        }
    }

    /// The deterministic on-disk location of a share artifact.
    private static func artifactURL(base: URL, id: UUID) -> URL {
        base.appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("index.html")
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Shares", isDirectory: true)
    }

    @discardableResult
    func share(messages: [AgentMessage], title: String, redactions: [String]) throws -> SharedSessionRecord {
        let id = UUID()
        let fileURL = SessionShareStore.artifactURL(base: baseDirectory, id: id)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let html = SessionShareRenderer.render(messages, title: title, redactions: redactions)
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        let record = SharedSessionRecord(id: id, title: title, createdAt: now(),
                                         filePath: fileURL.path)
        shares.insert(record, at: 0)
        save()
        return record
    }

    func delete(_ id: UUID) {
        guard let idx = shares.firstIndex(where: { $0.id == id }) else { return }
        let dir = baseDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        shares.remove(at: idx)
        save()
    }

    private func save() { persistence.save(SharedSessionsDocument(records: shares)) }
}
