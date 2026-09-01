import SwiftUI
import AinkradAppKit
import AinkradSignal

/// The bell's popover: a header and the shared feed list, nothing else. Any
/// filtering or searching belongs in the in-window island, which has the room
/// for it; this surface exists to answer "what happened while I was away?"
/// with the window closed.
struct SignalBellPopover: View {
    let events: [SignalEvent]
    var unread: Int
    var repeatCounts: [UUID: Int] = [:]
    var readIDs: Set<UUID> = []
    var now: Date = Date()
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }
    var onMarkAllRead: () -> Void = {}
    var onOpenFeed: () -> Void = {}

    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            SignalFeedList(events: events,
                           repeatCounts: repeatCounts,
                           readIDs: readIDs,
                           now: now,
                           onActivate: onActivate,
                           onAction: onAction)
        }
        .frame(width: 380)
        .frame(maxHeight: 520)
        .background(theme.surface)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Notifications")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.foreground)
            if unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(theme.accentPrimary))
            }
            Spacer()
            if unread > 0 {
                headerButton("Mark all read", action: onMarkAllRead)
            }
            headerButton("Open feed", action: onOpenFeed)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // No separator beneath the header: the day header's own scrim carries
        // the break when the list scrolls under it.
    }

    private func headerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(theme.accentPrimary)
    }
}
