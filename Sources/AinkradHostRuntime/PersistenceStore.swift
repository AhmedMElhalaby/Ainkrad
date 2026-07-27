import Foundation

/// The persistence seam: load/save/delete versioned documents by type.
/// Replaces M1's `SettingsStore`. Concrete stores: `FileDocumentStore`
/// (production) and `InMemoryPersistenceStore` (tests / utility).
/// `Sendable` is a real requirement, not a formality: the web/media/video/voice
/// routing backends all read settings from a store off the main actor. They
/// used to buy that with `nonisolated(unsafe)`, which silences the compiler
/// without making anything safe. Conformers must therefore synchronize their
/// own state — both in-tree ones do, with a lock.
public protocol PersistenceStore: AnyObject, Sendable {
    /// Returns the stored document, or `nil` if absent or unrecoverable.
    func load<T: PersistableDocument>(_ type: T.Type) -> T?
    /// Persists the document immediately.
    func save<T: PersistableDocument>(_ document: T)
    /// Removes the document if present.
    func delete<T: PersistableDocument>(_ type: T.Type)
}
