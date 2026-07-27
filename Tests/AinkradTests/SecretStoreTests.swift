import Testing
import Foundation
@testable import Ainkrad
import AinkradHostRuntime

@Suite("InMemorySecretStore")
struct InMemorySecretStoreTests {
    @Test("returns nil for an unknown id")
    func nilWhenUnknown() {
        #expect(InMemorySecretStore().secret(for: "x") == nil)
    }

    @Test("set then get round-trips, and nil deletes")
    func roundTripAndDelete() {
        let store = InMemorySecretStore()
        store.setSecret("token", for: "x")
        #expect(store.secret(for: "x") == "token")
        store.setSecret(nil, for: "x")
        #expect(store.secret(for: "x") == nil)
    }
}

/// Exercises the real Keychain. Requires a logged-in user session (local
/// `make test`); uses a unique service so runs never collide, and cleans up.
@Suite("KeychainSecretStore")
final class KeychainSecretStoreTests {
    let service = "com.ainkrad.tests.keychain.\(UUID().uuidString)"
    var store: KeychainSecretStore { KeychainSecretStore(service: service) }

    deinit {
        let s = KeychainSecretStore(service: service)
        for id in ["a", "b"] { s.setSecret(nil, for: id) }
    }

    @Test("returns nil for an unknown id")
    func nilWhenUnknown() {
        #expect(store.secret(for: "a") == nil)
    }

    @Test("set then get round-trips")
    func roundTrips() {
        store.setSecret("sk-123", for: "a")
        #expect(store.secret(for: "a") == "sk-123")
    }

    @Test("setting an existing id updates it")
    func updatesExisting() {
        store.setSecret("first", for: "b")
        store.setSecret("second", for: "b")
        #expect(store.secret(for: "b") == "second")
    }

    @Test("setting nil deletes the secret")
    func nilDeletes() {
        store.setSecret("gone", for: "a")
        store.setSecret(nil, for: "a")
        #expect(store.secret(for: "a") == nil)
    }
}
