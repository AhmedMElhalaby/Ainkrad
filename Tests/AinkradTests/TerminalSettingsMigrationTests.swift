import Testing
import Foundation
@testable import Ainkrad
import AinkradAppKit

private final class FakeDocs: PluginDocumentStore {
    var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func setData(_ data: Data?, forKey key: String) { storage[key] = data }
}

@Suite("TerminalSettingsMigration")
struct TerminalSettingsMigrationTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "com.ainkrad.tests.\(UUID().uuidString)")!
    }

    @Test("copies a legacy settings doc into the scoped store and sets the flag")
    func copiesLegacy() throws {
        let legacy = InMemoryPersistenceStore()
        legacy.save(TerminalSettings(defaultShell: "/bin/bash"))
        let scoped = FakeDocs()
        let d = defaults()

        TerminalSettingsMigration.runIfNeeded(legacy: legacy, scoped: scoped, defaults: d)

        let data = try #require(scoped.data(forKey: TerminalSettings.documentID))
        let decoded = try JSONDecoder().decode(TerminalSettings.self, from: data)
        #expect(decoded.defaultShell == "/bin/bash")
        #expect(d.bool(forKey: TerminalSettingsMigration.flagKey))
    }

    @Test("does nothing when the flag is already set")
    func skipsWhenFlagged() {
        let legacy = InMemoryPersistenceStore()
        legacy.save(TerminalSettings(defaultShell: "/bin/bash"))
        let scoped = FakeDocs()
        let d = defaults()
        d.set(true, forKey: TerminalSettingsMigration.flagKey)

        TerminalSettingsMigration.runIfNeeded(legacy: legacy, scoped: scoped, defaults: d)
        #expect(scoped.data(forKey: TerminalSettings.documentID) == nil)
    }

    @Test("with no legacy doc, sets the flag and writes nothing")
    func noLegacyDoc() {
        let scoped = FakeDocs()
        let d = defaults()
        TerminalSettingsMigration.runIfNeeded(legacy: InMemoryPersistenceStore(), scoped: scoped, defaults: d)
        #expect(scoped.data(forKey: TerminalSettings.documentID) == nil)
        #expect(d.bool(forKey: TerminalSettingsMigration.flagKey))
    }

    @Test("never overwrites an existing scoped doc")
    func doesNotOverwrite() {
        let legacy = InMemoryPersistenceStore()
        legacy.save(TerminalSettings(defaultShell: "/bin/bash"))
        let scoped = FakeDocs()
        scoped.setData(Data("existing".utf8), forKey: TerminalSettings.documentID)
        TerminalSettingsMigration.runIfNeeded(legacy: legacy, scoped: scoped, defaults: defaults())
        #expect(scoped.data(forKey: TerminalSettings.documentID) == Data("existing".utf8))
    }
}
