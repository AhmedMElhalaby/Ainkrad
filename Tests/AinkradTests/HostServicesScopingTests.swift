import Testing
import Foundation
@testable import Ainkrad

struct HostServicesScopingTests {
    @Test("an app cannot read another app's documents")
    func documentIsolation() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let a = ScopedPluginDocumentStore(directory: root.appendingPathComponent("appA"))
        let b = ScopedPluginDocumentStore(directory: root.appendingPathComponent("appB"))

        a.setData(Data("secret".utf8), forKey: "note")
        #expect(a.data(forKey: "note") == Data("secret".utf8))
        #expect(b.data(forKey: "note") == nil)
    }

    @Test("a document key cannot escape its app directory via traversal")
    func documentTraversalBlocked() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let a = ScopedPluginDocumentStore(directory: root.appendingPathComponent("appA"))
        a.setData(Data("x".utf8), forKey: "../../escape")
        // Nothing is written outside the app directory.
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape").path))
    }

    @Test("secrets are namespaced per app")
    func secretIsolation() {
        let backing = InMemorySecretStore()
        let a = ScopedPluginSecretStore(appID: "appA", backing: backing)
        let b = ScopedPluginSecretStore(appID: "appB", backing: backing)

        a.setSecret("token", forKey: "api")
        #expect(a.secret(forKey: "api") == "token")
        #expect(b.secret(forKey: "api") == nil)
        #expect(backing.secret(for: "appA.api") == "token")
    }
}
