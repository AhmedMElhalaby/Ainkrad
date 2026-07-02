import Testing
import Foundation
@testable import Ainkrad

private struct Sample: Codable, Equatable {
    let name: String
    let count: Int
}

@Suite("UserDefaultsSettingsStore")
final class UserDefaultsSettingsStoreTests {
    let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        self.defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("get returns nil when nothing has been set")
    func getReturnsNilWhenUnset() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        #expect(store.get(Sample.self, forKey: "sample") == nil)
    }

    @Test("set then get returns the same value")
    func setThenGetRoundTrips() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let value = Sample(name: "terminal", count: 3)

        store.set(value, forKey: "sample")

        #expect(store.get(Sample.self, forKey: "sample") == value)
    }

    @Test("a value survives a simulated relaunch (fresh store instance)")
    func valueSurvivesFreshStoreInstance() {
        let firstLaunch = UserDefaultsSettingsStore(defaults: defaults)
        firstLaunch.set(Sample(name: "settings", count: 7), forKey: "sample")

        let secondLaunch = UserDefaultsSettingsStore(defaults: defaults)

        #expect(secondLaunch.get(Sample.self, forKey: "sample") == Sample(name: "settings", count: 7))
    }
}
