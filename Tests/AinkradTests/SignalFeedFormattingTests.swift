import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@Suite("Signal feed formatting")
struct SignalFeedFormattingTests {
    private func event(_ title: String, at seconds: TimeInterval,
                       severity: SignalSeverity = .info) -> SignalEvent {
        SignalEvent(timestamp: Date(timeIntervalSince1970: seconds), source: .host,
                    kind: "test.event", severity: severity, title: title)
    }

    @Test("relative time is terse and never says '0 seconds ago'")
    func relativeTime() {
        let now = Date(timeIntervalSince1970: 100_000)
        #expect(SignalRowFormatter.relativeTime(now, now: now) == "now")
        #expect(SignalRowFormatter.relativeTime(now.addingTimeInterval(-30), now: now) == "now")
        #expect(SignalRowFormatter.relativeTime(now.addingTimeInterval(-90), now: now) == "1m")
        #expect(SignalRowFormatter.relativeTime(now.addingTimeInterval(-7200), now: now) == "2h")
        #expect(SignalRowFormatter.relativeTime(now.addingTimeInterval(-3 * 86400), now: now) == "3d")
    }

    @Test("events group into days, newest day first, newest event first within a day")
    func dayGrouping() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day0: TimeInterval = 1_756_684_800   // 2026-09-01 00:00 UTC
        let events = [
            event("today-early", at: day0 + 3600),
            event("today-late", at: day0 + 7200),
            event("yesterday", at: day0 - 3600),
        ]
        let groups = SignalRowFormatter.dayGroups(events, calendar: calendar)
        #expect(groups.count == 2)
        #expect(groups[0].events.map(\.title) == ["today-late", "today-early"])
        #expect(groups[1].events.map(\.title) == ["yesterday"])
    }

    @Test("each severity has a distinct symbol")
    func symbols() {
        let symbols = SignalSeverity.allCases.map(SignalRowFormatter.iconSymbol(for:))
        #expect(Set(symbols).count == SignalSeverity.allCases.count)
        #expect(SignalRowFormatter.iconSymbol(for: .failure) == "xmark.octagon")
    }
}
