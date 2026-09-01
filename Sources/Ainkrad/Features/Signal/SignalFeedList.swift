import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
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
                LazyVStack(alignment: .leading, spacing: AinkradSpacing.xs / 2,
                           pinnedViews: [.sectionHeaders]) {
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
                .padding(.vertical, AinkradSpacing.xs + 2)
                .padding(.horizontal, AinkradSpacing.xs + 2)
            }
        }
    }

    /// A header, not a separator: the design language forbids rules, so the day
    /// break is carried by weight and a soft scrim behind the pinned label.
    private func dayHeader(_ day: Date) -> some View {
        // Mono, uppercase, tracked: a date is a readout, and this is the same
        // treatment the top bar gives the clock.
        Text(Self.dayLabel(day, now: now, calendar: calendar))
            .font(AinkradFont.mono(9.5, weight: .semibold))
            .foregroundStyle(theme.foreground.opacity(0.42))
            .textCase(.uppercase)
            .tracking(0.7)
            .padding(.horizontal, AinkradSpacing.md)
            .padding(.top, AinkradSpacing.sm + 2)
            .padding(.bottom, AinkradSpacing.xs)
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
        VStack(spacing: AinkradSpacing.xs + 2) {
            Image(systemName: "bell.slash")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(theme.foreground.opacity(0.3))
            Text("Nothing yet")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.55))
            AinkradCaption("Runs, builds and app events will show up here.")
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AinkradSpacing.xl + AinkradSpacing.sm)
    }
}
