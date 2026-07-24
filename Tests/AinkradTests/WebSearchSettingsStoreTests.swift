import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("WebSearchSettingsStore")
@MainActor
struct WebSearchSettingsStoreTests {
    @Test func persistsProviderChoice() {
        let p = InMemoryPersistenceStore()
        let store = WebSearchSettingsStore(persistence: p)
        store.setProvider("brave")
        #expect(WebSearchSettingsStore(persistence: p).document.provider == "brave")
    }
}
