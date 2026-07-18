import Testing
import Foundation
@testable import Ainkrad

@Suite("Domain document conformance")
struct DocumentConformanceTests {
    @Test("document ids are stable and distinct")
    func stableDocumentIDs() {
        #expect(GlobalSettings.documentID == "global-settings")
        #expect(LayoutStateSnapshot.documentID == "workspace-layout")
        #expect(RegistryStateDocument.documentID == "registry-enabled-state")
        #expect(AgentsDocument.documentID == "agents")
        #expect(UsageLedgerDocument.documentID == "usage-ledger")
    }

    @Test("GlobalSettings round-trips through a persistence store")
    func globalSettingsRoundTrips() {
        let store = InMemoryPersistenceStore()
        store.save(GlobalSettings(theme: .cyberPurple))
        #expect(store.load(GlobalSettings.self) == GlobalSettings(theme: .cyberPurple))
    }

    @Test("RegistryStateDocument round-trips through a persistence store")
    func registryStateRoundTrips() {
        let store = InMemoryPersistenceStore()
        store.save(RegistryStateDocument(enabled: ["terminal": false]))
        #expect(store.load(RegistryStateDocument.self)?.enabled == ["terminal": false])
    }
}
