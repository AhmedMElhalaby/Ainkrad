import Foundation
import AinkradHostRuntime

/// Persisted enable/disable overrides for Built-in Apps, keyed by app id.
/// A wrapper so the registry's `[String: Bool]` can be a versioned document.
struct RegistryStateDocument: PersistableDocument {
    static let documentID = "registry-enabled-state"
    var enabled: [String: Bool] = [:]
}
