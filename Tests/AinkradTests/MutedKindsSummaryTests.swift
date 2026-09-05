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

    @Test("a row carries its source, so clearing does not go via the display name")
    func rowCarriesSource() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: rune, kind: "session.failed")
        let rows = MutedKindsSummary.rows(from: rules, displayName: name)
        #expect(rows.first { $0.kind == nil }?.source == raven)
        #expect(rows.first { $0.kind == "session.failed" }?.source == rune)
    }

    @Test("two sources sharing a display name stay distinct rows")
    func duplicateDisplayNames() {
        // The panel used to resolve a row back to its source by matching the
        // display name, so two apps called the same thing cleared each other.
        let one = SignalSource.app(appID: "a.raven")
        let two = SignalSource.app(appID: "b.raven")
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: one)
        SignalDeliveryMode.off.apply(to: &rules, source: two)
        let rows = MutedKindsSummary.rows(from: rules, displayName: { _ in "Raven" })
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.source)) == [one, two])
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
@Suite("Clearing a muted entry")
struct MutedKindsClearTests {
    private let raven = SignalSource.app(appID: "raven")
    private let rune = SignalSource.app(appID: "rune")

    @Test("clearing a whole-source row lifts both the mute and the override")
    func clearSource() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        let row = MutedKindsSummary.Row(id: "x", source: raven, sourceName: "Raven",
                                        kind: nil, mode: .off)
        MutedKindsSummary.clear(row, from: &rules)
        #expect(!rules.mutedSources.contains(raven))
        #expect(rules.sourceOverrides[raven] == nil)
    }

    @Test("clearing a kind row lifts only that kind")
    func clearKind() {
        var rules = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "build.warning")
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "build.failed")
        let row = MutedKindsSummary.Row(id: "x", source: raven, sourceName: "Raven",
                                        kind: "build.warning", mode: .feedOnly)
        MutedKindsSummary.clear(row, from: &rules)
        #expect(rules.sourceKindOverrides[SourceKind(source: raven, kind: "build.warning")] == nil)
        #expect(rules.sourceKindOverrides[SourceKind(source: raven, kind: "build.failed")] == [.feed])
    }

    @Test("a source the settings list has never seen can still be cleared")
    func clearsUnlistedSource() {
        // The regression this exists for: `clear` resolved the row through the
        // pane's `sources`, which is filtered by `hasEverEmitted`. A source
        // muted from a feed row's context menu was therefore listed with a
        // Restore button that did nothing.
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: rune)
        let row = MutedKindsSummary.rows(from: rules, displayName: { _ in "Rune" })[0]
        MutedKindsSummary.clear(row, from: &rules)
        #expect(rules.mutedSources.isEmpty)
    }

    @Test("clearing one of two identically named sources leaves the other muted")
    func clearsOnlyTheNamedSource() {
        let one = SignalSource.app(appID: "a.raven")
        let two = SignalSource.app(appID: "b.raven")
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: one)
        SignalDeliveryMode.off.apply(to: &rules, source: two)
        let rows = MutedKindsSummary.rows(from: rules, displayName: { _ in "Raven" })
        MutedKindsSummary.clear(rows.first { $0.source == one }!, from: &rules)
        #expect(rules.mutedSources == [two])
    }
}

@MainActor
@Suite("Sources the settings pane lists")
struct SignalSettingsSourcesTests {
    private let raven = SignalSource.app(appID: "raven")
    private let rune = SignalSource.app(appID: "rune")

    @Test("nothing configured names nothing")
    func empty() {
        #expect(SignalSettingsPane.configuredSources(in: .default).isEmpty)
    }

    @Test("every rule that names a source contributes it")
    func everyRuleContributes() {
        var rules = RoutingRules.default
        SignalDeliveryMode.off.apply(to: &rules, source: raven)
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: rune, kind: "session.failed")
        #expect(SignalSettingsPane.configuredSources(in: rules) == [raven, rune])
    }

    @Test("a floor, a cue or a bypass alone is enough to be listed")
    func quietConfiguration() {
        // Each of these is a setting the user made and must be able to find
        // again, even for a source that has never emitted.
        var rules = RoutingRules.default
        rules.interruptFloor[raven] = .warning
        #expect(SignalSettingsPane.configuredSources(in: rules) == [raven])

        var cue = RoutingRules.default
        cue.soundOverride[rune] = .silent
        #expect(SignalSettingsPane.configuredSources(in: cue) == [rune])

        var bypass = RoutingRules.default
        bypass.urgentBypass.insert(raven)
        #expect(SignalSettingsPane.configuredSources(in: bypass) == [raven])
    }
}

@MainActor
@Suite("Notification vocabulary")
struct SignalVocabularyTests {
    private let raven = SignalSource.app(appID: "raven")

    @Test("the three delivery states read Alert, Quiet, Off")
    func deliveryLabels() {
        // One ladder, three words, used in every surface. "Feed only" described
        // the mechanism; "Quiet" describes what the user gets, and stops the
        // "it is still in the feed" hint having to be printed beside every
        // control that can silence something.
        #expect(SignalDeliveryMode.everything.label == "Alert")
        #expect(SignalDeliveryMode.feedOnly.label == "Quiet")
        #expect(SignalDeliveryMode.off.label == "Off")
    }

    @Test("the row menu speaks the same three words")
    func rowMenuVocabulary() {
        let event = SignalEvent(timestamp: Date(timeIntervalSince1970: 0), source: raven,
                                kind: "build.failed", severity: .failure,
                                title: "Build failed", body: nil)
        func titles(_ rules: RoutingRules) -> [String] {
            SignalRowMenu.items(for: event, rules: rules, sourceName: "Raven",
                                isRead: false, isPinned: false,
                                onMuteKind: {}, onUnmuteKind: {}, onMuteSource: {},
                                onToggleRead: {}, onCopy: {}, onDismiss: {},
                                onTogglePin: {}).map(\.title)
        }
        #expect(titles(.default).contains("Quiet Raven › build.failed"))
        #expect(titles(.default).contains("Turn off everything from Raven"))

        var quieted = RoutingRules.default
        SignalDeliveryMode.feedOnly.apply(to: &quieted, source: raven, kind: "build.failed")
        #expect(titles(quieted).contains("Alert me about Raven › build.failed"))
    }

    @Test("no surface reintroduces a fourth word for silence")
    func noStrayVerbs() {
        // The feature used to carry seven: mute, unmute, muted, silence, off,
        // feed only, turn back on. A regression here is a user reading two
        // words for one state and assuming they are two states.
        let event = SignalEvent(timestamp: Date(timeIntervalSince1970: 0), source: raven,
                                kind: "build.failed", severity: .failure,
                                title: "Build failed", body: nil)
        let titles = SignalRowMenu.items(
            for: event, rules: .default, sourceName: "Raven",
            isRead: false, isPinned: false,
            onMuteKind: {}, onUnmuteKind: {}, onMuteSource: {},
            onToggleRead: {}, onCopy: {}, onDismiss: {}, onTogglePin: {}).map(\.title)
        #expect(!titles.contains { $0.lowercased().contains("mute") })
        #expect(!titles.contains { $0.lowercased().contains("silence") })
    }
}

@MainActor
@Suite("Snooze")
struct SignalSnoozeTests {
    @Test("exactly two options, offered identically everywhere")
    func twoOptions() {
        // The dropdown offered one hour, Settings offered two choices and the
        // overlay offered none. Same action, three surfaces, three answers.
        #expect(SignalSnooze.allCases.count == 2)
        #expect(SignalSnooze.allCases.map(\.label)
                == ["Quiet for an hour", "Quiet until tomorrow"])
    }

    @Test("an hour is an hour")
    func anHour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SignalSnooze.hour.until(after: now) == now.addingTimeInterval(3600))
    }

    @Test("until tomorrow means the working morning, not midnight")
    func tomorrowMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 9, day: 3, hour: 23))!

        let resume = SignalSnooze.tomorrow.until(after: now, calendar: calendar)

        // Midnight would end it an hour later, in the middle of the night —
        // which is not what anyone means by "until tomorrow".
        let parts = calendar.dateComponents([.day, .hour], from: resume)
        #expect(parts.day == 4)
        #expect(parts.hour == 8)
    }

    @Test("applying a snooze writes the same field quiet hours reads")
    func appliesToSuppression() {
        var suppression = SuppressionWindow()
        let now = Date(timeIntervalSince1970: 1_000_000)
        SignalSnooze.hour.apply(to: &suppression, at: now)
        #expect(suppression.isSuppressing(at: now))
        #expect(!suppression.isSuppressing(at: now.addingTimeInterval(3601)))
    }

    @Test("lifting a snooze leaves the schedule alone")
    func liftKeepsSchedule() {
        // A user ending an ad-hoc quiet spell has not asked to be woken at 3am.
        var suppression = SuppressionWindow(quietStartMinute: 22 * 60,
                                            quietEndMinute: 7 * 60)
        SignalSnooze.tomorrow.apply(to: &suppression, at: Date())
        SignalSnooze.lift(&suppression)
        #expect(suppression.snoozedUntil == nil)
        #expect(suppression.quietStartMinute == 22 * 60)
        #expect(suppression.quietEndMinute == 7 * 60)
    }
}
