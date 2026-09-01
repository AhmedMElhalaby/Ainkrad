import SwiftUI
import AinkradAppKit
import AinkradSignal

/// Day-grouped list of events. Deliberately dumb: it owns no state and reads
/// no store, because both the bell popover and the in-window island embed it.
struct SignalFeedList: View {
    let events: [SignalEvent]
    var repeatCounts: [UUID: Int] = [:]
    var readIDs: Set<UUID> = []
    var now: Date = Date()
    var calendar: Calendar = .current
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }

    @Environment(\.ainkradTheme) private var theme

    private var groups: [SignalDayGroup] {
        SignalRowFormatter.dayGroups(events, calendar: calendar)
    }

    var body: some View {
        if events.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.events) { event in
                                SignalFeedRow(event: event,
                                              repeatCount: repeatCounts[event.id] ?? 1,
                                              isUnread: !readIDs.contains(event.id),
                                              now: now,
                                              onActivate: onActivate,
                                              onAction: onAction)
                            }
                        } header: {
                            dayHeader(group.id)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
        }
    }

    /// A header, not a separator: the design language forbids rules, so the day
    /// break is carried by weight and a soft scrim behind the pinned label.
    private func dayHeader(_ day: Date) -> some View {
        Text(Self.dayLabel(day, now: now, calendar: calendar))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.foreground.opacity(0.42))
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface.opacity(0.92))
    }

    static func dayLabel(_ day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: day)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.slash")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(theme.foreground.opacity(0.3))
            Text("Nothing yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.55))
            Text("Runs, builds and app events will show up here.")
                .font(.system(size: 11))
                .foregroundStyle(theme.foreground.opacity(0.38))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}
