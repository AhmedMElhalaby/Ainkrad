import SwiftUI
import AinkradAppKit
import AinkradSignal

/// Positions `SignalBellDropdown` under the bell and dismisses it on an
/// outside click.
///
/// No scrim tint: a dropdown is not a modal, and dimming the workspace behind
/// a five-row glance would read as one. The catcher is transparent and exists
/// only to take the outside click.
struct SignalBellDropdownOverlay: View {
    let center: SignalCenter
    let onDismiss: () -> Void
    let onViewAll: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            SignalBellDropdown(
                events: center.recent,
                unread: center.totalUnread,
                repeatCounts: center.repeatCounts,
                readIDs: center.readIDs,
                onActivate: { event in
                    center.markRead(ids: [event.id])
                },
                onMarkAllRead: { center.markAllRead(filter: .all) },
                onViewAll: onViewAll)
                // Clear of the 30pt top bar, and inset from the trailing edge
                // so it hangs under the bell rather than the workspace dots.
                .padding(.top, 34)
                .padding(.trailing, 10)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity))
        }
        .ignoresSafeArea()
    }
}
