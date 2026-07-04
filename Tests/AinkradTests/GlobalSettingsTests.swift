import Testing
import Foundation
@testable import Ainkrad

@Suite("GlobalSettings")
final class GlobalSettingsTests {
    @Test("defaults to Neon Blue with no prior write")
    func defaultsToNeonBlue() {
        let store = InMemoryPersistenceStore()
        let loaded = store.load(GlobalSettings.self) ?? GlobalSettings()
        #expect(loaded.theme == .neonBlue)
    }

    @Test("a written Cyber Purple selection round-trips through the persistence store")
    func cyberPurpleRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.theme = .cyberPurple
        store.save(settings)
        #expect(store.load(GlobalSettings.self)?.theme == .cyberPurple)
    }

    @Test("appIcon defaults to Auto")
    func appIconDefaultsToAuto() {
        #expect(GlobalSettings().appIcon == .auto)
    }

    @Test("an explicit appIcon choice round-trips through the persistence store")
    func appIconRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.appIcon = .purple
        store.save(settings)

        #expect(store.load(GlobalSettings.self)?.appIcon == .purple)
    }

    @Test("a legacy payload without appIcon decodes to Auto")
    func legacyPayloadDecodesToAuto() throws {
        let legacy = Data(#"{"theme":"cyberPurple"}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.theme == .cyberPurple)
        #expect(decoded.appIcon == .auto)
    }
}
