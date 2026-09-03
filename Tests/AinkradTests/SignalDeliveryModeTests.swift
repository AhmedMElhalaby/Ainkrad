import Testing
import AinkradSignal
@testable import Ainkrad

@Suite("Signal delivery mode")
struct SignalDeliveryModeTests {
    private let raven = SignalSource.app(appID: "raven")

    @Test("a source nobody has configured is on everything")
    func defaultIsEverything() {
        #expect(SignalDeliveryMode(rules: .default, source: raven) == .everything)
    }

    @Test("feed-only records without interrupting, and reads back as feed-only")
    func feedOnlyRoundTrips() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven)
        #expect(rules.sourceOverrides[raven] == [.feed])
        #expect(!rules.mutedSources.contains(raven))
        #expect(SignalDeliveryMode(rules: rules, source: raven) == .feedOnly)
    }

    @Test("off mutes, and mute outranks any override")
    func offMutes() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        #expect(rules.mutedSources.contains(raven))
        #expect(SignalDeliveryMode(rules: rules, source: raven) == .off)
    }

    @Test("everything clears both the mute and the override")
    func everythingClears() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven)
        SignalDeliveryMode.everything.apply(to: &rules, source: raven)
        #expect(rules.sourceOverrides[raven] == nil)
        #expect(!rules.mutedSources.contains(raven))
    }

    @Test("everything stores no channel set, so evolving defaults still apply")
    func everythingIsNotAFrozenSnapshot() {
        var rules = RoutingRules.default
        SignalDeliveryMode.everything.apply(to: &rules, source: raven)
        // Writing today's full channel set would freeze today's severity table
        // into the user's preferences file for good.
        #expect(rules.sourceOverrides[raven] == nil)
    }

    @Test("each mode changes only the source it names")
    func modesArePerSource() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        #expect(SignalDeliveryMode(rules: rules, source: .host) == .everything)
    }

    @Test("a richer override from a later phase reads as everything, not as broken")
    func unrepresentableOverrideDegradesGracefully() {
        var rules = RoutingRules.default
        rules.sourceOverrides[raven] = [.feed, .badge]
        #expect(SignalDeliveryMode(rules: rules, source: raven) == .everything)
    }
}
