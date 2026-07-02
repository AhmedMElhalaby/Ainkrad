import Testing
import Foundation
@testable import Ainkrad

@Suite("TerminalSettings")
final class TerminalSettingsTests {
    let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { self.defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }

    @Test("defaults to nil shell and working directory with no prior write")
    func defaultsToNilFields() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let loaded = store.get(TerminalSettings.self, forKey: TerminalSettings.storeKey) ?? TerminalSettings()
        #expect(loaded.defaultShell == nil)
        #expect(loaded.defaultWorkingDirectory == nil)
    }

    @Test("a written selection round-trips through SettingsStore")
    func writtenSelectionRoundTrips() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = TerminalSettings()
        settings.defaultShell = "/bin/bash"
        settings.defaultWorkingDirectory = URL(fileURLWithPath: "/tmp")
        store.set(settings, forKey: TerminalSettings.storeKey)

        let loaded = store.get(TerminalSettings.self, forKey: TerminalSettings.storeKey)

        #expect(loaded?.defaultShell == "/bin/bash")
        #expect(loaded?.defaultWorkingDirectory == URL(fileURLWithPath: "/tmp"))
    }
}
