import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@Suite("SignalPreferences")
struct SignalPreferencesTests {
    private func makeStore() -> (SignalPreferencesStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-prefs-\(UUID().uuidString).json")
        return (SignalPreferencesStore(url: url), url)
    }

    @Test("defaults are returned when nothing is saved")
    func defaults() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let prefs = store.load()
        #expect(prefs.rules == .default)
        #expect(prefs.retention == .default)
    }

    @Test("saved rules survive a round trip, including muted sources and overrides")
    func roundTrip() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        var rules = RoutingRules.default
        rules.mutedSources.insert(.app(appID: "raven"))
        rules.sourceKindOverrides[SourceKind(source: .host, kind: "run.finished")] = [.feed, .toast]
        store.save(SignalPreferences(rules: rules, retention: RetentionPolicy(maxAgeDays: 7, maxEvents: 500)))

        let loaded = SignalPreferencesStore(url: url).load()
        #expect(loaded.rules.mutedSources.contains(.app(appID: "raven")))
        #expect(loaded.rules.sourceKindOverrides[SourceKind(source: .host, kind: "run.finished")] == [.feed, .toast])
        #expect(loaded.retention.maxAgeDays == 7)
    }

    @Test("a corrupt file falls back to defaults rather than throwing")
    func corruptFileFallsBack() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(store.load().rules == .default)
    }

    @Test("preferences written before the exemption was removed still load")
    func decodesPreExemptionPreferences() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-prefs-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // Exactly what M1 wrote, including the flag that no longer exists.
        // `RoutingRules` is Codable with synthesized conformance, so an unknown
        // key is ignored on decode — asserted rather than assumed, because if it
        // were not, every user who changed a notification setting in M1 would
        // silently lose all of them on upgrade.
        let legacy = """
        {"rules":{"mutedSources":[],"sourceOverrides":[],"sourceKindOverrides":[],
        "suppressBannerForHostRuns":true},
        "retention":{"maxAgeDays":7,"maxEvents":500}}
        """
        try Data(legacy.utf8).write(to: url)

        let loaded = SignalPreferencesStore(url: url).load()
        #expect(loaded.retention.maxAgeDays == 7, "the user's retention choice survives")
        #expect(loaded.retention.maxEvents == 500)
        #expect(loaded.rules == .default)
    }
}
