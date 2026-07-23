import Foundation

/// Stores small secrets (API tokens) keyed by an opaque id. Backed by the
/// macOS Keychain in production; secrets are NEVER written to JSON documents,
/// export bundles, or logs. Passing `nil` to `setSecret` deletes.
public protocol SecretStore: AnyObject {
    func secret(for id: String) -> String?
    func setSecret(_ value: String?, for id: String)
}

/// In-memory `SecretStore` for tests.
public final class InMemorySecretStore: SecretStore {
    private var storage: [String: String] = [:]

    public init() {}

    public func secret(for id: String) -> String? { storage[id] }

    public func setSecret(_ value: String?, for id: String) {
        storage[id] = value
    }
}
