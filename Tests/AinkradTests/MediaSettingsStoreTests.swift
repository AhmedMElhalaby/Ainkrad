import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("MediaSettingsStore")
@MainActor
struct MediaSettingsStoreTests {
    @Test func persistsProviderChoice() {
        let p = InMemoryPersistenceStore()
        MediaSettingsStore(persistence: p).setProvider("openai")
        #expect(MediaSettingsStore(persistence: p).document.provider == "openai")
    }
}
