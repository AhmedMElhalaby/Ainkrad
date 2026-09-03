import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Muted kinds summary")
struct MutedKindsSummaryTests {
    private let raven = SignalSource.app(appID: "raven")
    private let rune = SignalSource.app(appID: "rune")
    private func name(_ source: SignalSource) -> String {
        switch source {
        case .app(let id): return id.capitalized
        case .host: return "Ainkrad"
        case .sage: return "Sage"
        @unknown default: return "Ainkrad"
        }
    }

    @Test("nothing configured lists nothing")
    func emptyRules() {
        #expect(MutedKindsSummary.rows(from: .default, displayName: name).isEmpty)
    }

    @Test("a muted source is listed as off")
    func mutedSource() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        let rows = MutedKindsSummary.rows(from: rules, displayName: name)
        #expect(rows.count == 1)
        #expect(rows[0].sourceName == "Raven")
        #expect(rows[0].kind == nil)
        #expect(rows[0].mode == .off)
    }

    @Test("a feed-only source is listed once, not twice")
    func feedOnlySourceListedOnce() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven)
        #expect(MutedKindsSummary.rows(from: rules, displayName: name).count == 1)
    }

    @Test("a muted source is not also listed as feed-only")
    func mutedIsNotAlsoFeedOnly() {
        var rules = RoutingRules.default
        rules.sourceOverrides[raven] = [.feed]
        rules.mutedSources.insert(raven)
        // Mute outranks the override in `route`, so listing both would tell the
        // user two things about one source, one of which is not what happens.
        let rows = MutedKindsSummary.rows(from: rules, displayName: name)
        #expect(rows.count == 1)
        #expect(rows[0].mode == .off)
    }

    @Test("per-kind mutes are listed with their kind")
    func kindRows() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "build.warning")
        let rows = MutedKindsSummary.rows(from: rules, displayName: name)
        #expect(rows.count == 1)
        #expect(rows[0].kind == "build.warning")
        #expect(rows[0].sourceName == "Raven")
    }

    @Test("whole-source entries sort before kinds, each alphabetically")
    func stableOrdering() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: rune, kind: "session.failed")
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "build.warning")
        SignalDeliveryMode.off.apply(to: &rules, source: rune)
        let rows = MutedKindsSummary.rows(from: rules, displayName: name)
        // A stable order matters because the user removes entries from this
        // list: one that reshuffles on every removal makes them lose their place.
        #expect(rows.map { [$0.sourceName, $0.kind ?? "-"] }
                == [["Rune", "-"], ["Raven", "build.warning"], ["Rune", "session.failed"]])
    }

    @Test("every row has a distinct id, so the list does not collapse")
    func idsAreDistinct() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "a")
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "b")
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        let rows = MutedKindsSummary.rows(from: rules, displayName: name)
        #expect(Set(rows.map(\.id)).count == rows.count)
    }
}

@MainActor
@Suite("Quiet hours helpers")
struct QuietHoursHelperTests {
    @Test("until tomorrow means the working morning, not midnight")
    func tomorrowMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 9, day: 3, hour: 23))!

        let resume = GlobalNotificationSettings.tomorrowMorning(after: now, calendar: calendar)

        // Midnight would end the mute an hour later, in the middle of the
        // night — which is not what anyone means by "until tomorrow".
        let parts = calendar.dateComponents([.day, .hour], from: resume)
        #expect(parts.day == 4)
        #expect(parts.hour == 8)
    }
}
