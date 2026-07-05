import Testing
import Foundation
import Observation
@testable import Ainkrad
import AinkradAppKit

private final class FakeDocs: PluginDocumentStore {
    var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func setData(_ data: Data?, forKey key: String) { storage[key] = data }
}

/// Reference box so the observation `onChange` closure (which Swift 6 treats as
/// concurrently-executing) can record that it fired without mutating a captured
/// local `var`.
private final class Flag: @unchecked Sendable {
    var fired = false
}

@Suite("TerminalSettingsStore")
@MainActor
struct TerminalSettingsStoreTests {
    @Test("loads defaults when the scoped store is empty")
    func loadsDefaults() {
        let store = TerminalSettingsStore(documents: FakeDocs())
        #expect(store.settings.colorSchemeID == TerminalColorScheme.matchThemeID)
    }

    @Test("an update persists and reloads through the scoped store")
    func updatePersists() {
        let docs = FakeDocs()
        let store = TerminalSettingsStore(documents: docs)
        store.update { $0.fontFamily = "Menlo"; $0.fontSize = 16 }
        let reloaded = TerminalSettingsStore(documents: docs)
        #expect(reloaded.settings.fontFamily == "Menlo")
        #expect(reloaded.settings.fontSize == 16)
    }

    @Test("an update publishes an observation change")
    func updatePublishes() {
        let store = TerminalSettingsStore(documents: FakeDocs())
        let flag = Flag()
        withObservationTracking { _ = store.settings } onChange: { flag.fired = true }
        store.update { $0.cursorBlink = false }
        #expect(flag.fired)
    }
}
