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
