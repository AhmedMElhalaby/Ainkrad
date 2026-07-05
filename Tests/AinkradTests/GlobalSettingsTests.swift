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

    @Test("a legacy payload with an extra unknown field still decodes the theme")
    func legacyPayloadWithExtraFieldDecodes() throws {
        let legacy = Data(#"{"theme":"cyberPurple","appIcon":"purple"}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.theme == .cyberPurple)
    }

    @Test("a payload without theme decodes to the Neon Blue default")
    func missingThemeDecodesToDefault() throws {
        let legacy = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.theme == .neonBlue)
    }
}
