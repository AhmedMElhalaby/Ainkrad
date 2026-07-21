import Foundation
import Testing
@testable import Ainkrad

@Suite("Model discovery cache")
struct ModelDiscoveryCacheTests {
    let id = UUID()
    let ttl: TimeInterval = 300

    @Test("fetches when never fetched") func neverFetched() {
        #expect(shouldFetchModels(connectionID: id, now: Date(), lastFetch: [:], inFlight: [], ttl: ttl) == true)
    }
    @Test("skips when a fetch is already in flight") func inFlightSkips() {
        #expect(shouldFetchModels(connectionID: id, now: Date(), lastFetch: [:], inFlight: [id], ttl: ttl) == false)
    }
    @Test("skips when the cached entry is younger than the TTL") func freshSkips() {
        let now = Date()
        #expect(shouldFetchModels(connectionID: id, now: now, lastFetch: [id: now.addingTimeInterval(-60)], inFlight: [], ttl: ttl) == false)
    }
    @Test("fetches when the cached entry is older than the TTL") func staleFetches() {
        let now = Date()
        #expect(shouldFetchModels(connectionID: id, now: now, lastFetch: [id: now.addingTimeInterval(-600)], inFlight: [], ttl: ttl) == true)
    }
}

/// Locks in that the composer's Auto pill selection is a stable sentinel — it
/// resolves to `.auto` whenever the router is on and nothing is pinned, so the
/// trigger shows a steady "Auto" and never substitutes a mid-turn resolved
/// model (which would visibly jump on settle).
@Suite("Auto pill stability")
struct AutoPillStabilityTests {
    @Test("Auto selection is stable regardless of last-resolved model") func stable() {
        #expect(modelPillSelectionIsAuto(pinnedModel: nil, routerEnabled: true) == true)
        // A pin always wins over Auto (matches ModelRouter pin precedence).
        #expect(modelPillSelectionIsAuto(pinnedModel: "gpt-x", routerEnabled: true) == false)
        // Router off + no pin → not Auto (shows the standing default, also stable).
        #expect(modelPillSelectionIsAuto(pinnedModel: nil, routerEnabled: false) == false)
    }

    @Test("a pin is displayed verbatim and never overridden by the resolved model") func pinWins() {
        #expect(modelPillDisplayModel(pinnedModel: "claude-x", routerEnabled: true,
                                      lastResolvedModel: "gpt-y", standingDefault: "d") == "claude-x")
    }
}
