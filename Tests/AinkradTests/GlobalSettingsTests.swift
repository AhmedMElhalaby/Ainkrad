import Testing
import Foundation
@testable import Ainkrad

@Suite("GlobalSettings")
final class GlobalSettingsTests {
    let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { self.defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }

    @Test("defaults to Neon Blue with no prior write")
    func defaultsToNeonBlue() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let loaded = store.get(GlobalSettings.self, forKey: "global-settings") ?? GlobalSettings()
        #expect(loaded.theme == .neonBlue)
    }

    @Test("a written Cyber Purple selection round-trips through SettingsStore")
    func cyberPurpleRoundTrips() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = GlobalSettings()
        settings.theme = .cyberPurple
        store.set(settings, forKey: "global-settings")

        let loaded = store.get(GlobalSettings.self, forKey: "global-settings")

        #expect(loaded?.theme == .cyberPurple)
    }
}
