import Foundation

/// Seam for a future cross-device sync backend. Not implemented in M2 — the
/// store notifies it on every save so a later engine can observe changes. The
/// document envelope's `schemaVersion` + `updatedAt` are the versioning basis
/// for conflict resolution.
public protocol SyncEngine: AnyObject {
    /// Called after a document is written, with the encoded envelope bytes.
    func documentDidChange(id: String, data: Data)
    /// Begins syncing (e.g. at launch). No-op in M2.
    func start()
}

/// The default engine: does nothing. Keeps call sites unconditional.
public final class NoOpSyncEngine: SyncEngine {
    public init() {}
    public func documentDidChange(id: String, data: Data) {}
    public func start() {}
}
