import Foundation

/// The persistence seam: load/save/delete versioned documents by type.
/// Replaces M1's `SettingsStore`. Concrete stores: `FileDocumentStore`
/// (production) and `InMemoryPersistenceStore` (tests / utility).
protocol PersistenceStore: AnyObject {
    /// Returns the stored document, or `nil` if absent or unrecoverable.
    func load<T: PersistableDocument>(_ type: T.Type) -> T?
    /// Persists the document immediately.
    func save<T: PersistableDocument>(_ document: T)
    /// Removes the document if present.
    func delete<T: PersistableDocument>(_ type: T.Type)
}
