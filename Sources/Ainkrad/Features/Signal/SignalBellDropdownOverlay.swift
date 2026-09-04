import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Positions `SignalBellDropdown` under the bell and dismisses it on an
/// outside click.
///
/// No scrim tint: a dropdown is not a modal, and dimming the workspace behind
/// a five-row glance would read as one. The catcher is transparent and exists
/// only to take the outside click.
struct SignalBellDropdownOverlay: View {
    let center: SignalCenter
    var hub: SignalEmitterHub?
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
                    center.activate(event)
                    onDismiss()
                },
                onAction: { event, action in
                    // The dropdown has no room for a confirmation dialog, so a
                    // destructive action hands off to the overlay rather than
                    // firing unconfirmed.
                    guard let hub else { return }
                    if SignalActionRouter(hub: hub).invoke(event, action) != nil { onViewAll() }
                },
                onMarkAllRead: { center.markAllRead(filter: .all) },
                onViewAll: onViewAll,
                isMuted: center.rules.suppression.isSuppressing(at: Date()),
                onToggleMute: {
                    // A snooze set here is the same field quiet hours use, so
                    // the two cannot disagree about whether now is quiet.
                    if center.rules.suppression.isSuppressing(at: Date()) {
                        center.rules.suppression.snoozedUntil = nil
                    } else {
                        center.rules.suppression.snoozedUntil =
                            Date().addingTimeInterval(3600)
                    }
                })
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
