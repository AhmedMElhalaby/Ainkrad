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
        #expect(prefs.rules.suppressBannerForHostRuns, "M1 ships with the run exemption on")
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
}
