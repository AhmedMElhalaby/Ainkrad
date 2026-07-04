import Foundation

/// Stores small secrets (API tokens) keyed by an opaque id. Backed by the
/// macOS Keychain in production; secrets are NEVER written to JSON documents,
/// export bundles, or logs. Passing `nil` to `setSecret` deletes.
protocol SecretStore: AnyObject {
    func secret(for id: String) -> String?
    func setSecret(_ value: String?, for id: String)
}

/// In-memory `SecretStore` for tests.
final class InMemorySecretStore: SecretStore {
    private var storage: [String: String] = [:]

    func secret(for id: String) -> String? { storage[id] }

    func setSecret(_ value: String?, for id: String) {
        storage[id] = value
    }
}
