import Testing
import Foundation
@testable import Ainkrad

@Suite("LegacyUserDefaultsMigration")
final class LegacyUserDefaultsMigrationTests {
    let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }

    private func seedLegacy() {
        defaults.set(try! JSONEncoder().encode(GlobalSettings(theme: .cyberPurple, appIcon: .purple)),
                     forKey: "global-settings")
        defaults.set(try! JSONEncoder().encode(["terminal": false]), forKey: "registry-enabled-state")
        defaults.set(try! JSONEncoder().encode(TerminalSettings(defaultShell: "/bin/bash")),
                     forKey: "terminal-settings")
    }

    @Test("imports legacy values into the persistence store")
    func importsLegacyValues() {
        seedLegacy()
        let store = InMemoryPersistenceStore()
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults)

        #expect(store.load(GlobalSettings.self)?.theme == .cyberPurple)
        #expect(store.load(RegistryStateDocument.self)?.enabled == ["terminal": false])
        #expect(store.load(TerminalSettings.self)?.defaultShell == "/bin/bash")
    }

    @Test("does not run a second time once the marker is set")
    func runsOnlyOnce() {
        seedLegacy()
        let store = InMemoryPersistenceStore()
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults)

        // Mutate the imported doc, then re-run: a second import would overwrite it.
        store.save(GlobalSettings(theme: .neonBlue, appIcon: .auto))
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults)

        #expect(store.load(GlobalSettings.self)?.theme == .neonBlue)
    }

    @Test("no legacy data is a clean no-op that still sets the marker")
    func noLegacyDataNoOp() {
        let store = InMemoryPersistenceStore()
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults)
        #expect(store.load(GlobalSettings.self) == nil)
        #expect(store.load(LegacyUserDefaultsMigration.LegacyImportMarker.self)?.didImport == true)
    }
}
