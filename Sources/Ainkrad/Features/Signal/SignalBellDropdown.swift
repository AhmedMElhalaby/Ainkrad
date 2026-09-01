import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The bell's dropdown: a compact glance at what just happened, wearing the
/// shared HUD panel finish (`AinkradPanel` — blur, chamfered clip, luminous
/// accent stroke, corner brackets) rather than a hand-rolled rectangle.
///
/// It shows only the most recent few events. "View all notifications" hands
/// off to the full feed overlay, which is where search, filters and history
/// live — a dropdown that tried to carry those would be the overlay, just
/// smaller and worse.
struct SignalBellDropdown: View {
    let events: [SignalEvent]
    let unread: Int
    var repeatCounts: [UUID: Int] = [:]
    var readIDs: Set<UUID> = []
    var now: Date = Date()
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }
    var onMarkAllRead: () -> Void = {}
    var onViewAll: () -> Void = {}

    @Environment(\.ainkradTheme) private var theme

    /// Five is the most that fits without the dropdown becoming a scroll view,
    /// which is the point at which it should have been the overlay instead.
    private static let maxRows = 5

    private var shown: [SignalEvent] { Array(events.prefix(Self.maxRows)) }

    var body: some View {
        AinkradPanel(showsBrackets: true) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if shown.isEmpty {
                    empty
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(shown) { event in
                            SignalFeedRow(event: event,
                                          repeatCount: repeatCounts[event.id] ?? 1,
                                          isUnread: !readIDs.contains(event.id),
                                          now: now,
                                          onActivate: onActivate,
                                          onAction: onAction)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
                footer
            }
            .frame(width: 372)
        }
    }

    private var header: some View {
        HStack(spacing: AinkradSpacing.sm - 1) {
            Text("Notifications")
                .font(AinkradFont.display(11.5, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .textCase(.uppercase)
                .tracking(0.6)
            if unread > 0 {
                AinkradBadge(text: "\(unread)", tint: theme.accentSecondary)
            }
            Spacer()
            if unread > 0 {
                Button(action: onMarkAllRead) {
                    Text("Mark all read")
                        .font(AinkradFont.display(10, weight: .medium))
                        .foregroundStyle(theme.accentPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// The hand-off. Chevron rather than an ellipsis: it goes somewhere.
    private var footer: some View {
        Button(action: onViewAll) {
            HStack(spacing: 5) {
                Text(events.count > Self.maxRows
                     ? "View all \(events.count) notifications"
                     : "View all notifications")
                    .font(AinkradFont.display(10.5, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(theme.accentPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            // A tint band, not a separator line: the design language forbids
            // rules, and the footer still has to read as a distinct target.
            .background(theme.surfaceElevated.opacity(0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "bell.slash")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(theme.foreground.opacity(0.3))
            Text("Nothing yet")
                .font(AinkradFont.display(11, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
