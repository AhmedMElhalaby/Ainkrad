import SwiftUI
import AinkradAppKit
import AinkradSignal

/// Hosts `SignalFeedIsland` as a dismissible overlay, matching the other HUD
/// overlays (scrim tap to dismiss, fade transition, no separator chrome).
struct SignalFeedOverlayView: View {
    let center: SignalCenter
    let onDismiss: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @State private var searchResults: [SignalEvent]?

    private var events: [SignalEvent] { searchResults ?? center.recent }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            // The shared HUD panel finish, same as every other overlay in the
            // app: blur backing, chamfered clip, luminous accent stroke and
            // corner brackets. A plain rounded rectangle read as a web modal.
            AinkradPanel(showsBrackets: true) {
                SignalFeedIsland(
                    events: events,
                    unread: center.totalUnread,
                    repeatCounts: center.repeatCounts,
                    readIDs: center.readIDs,
                    knownSources: knownSources,
                    isDegraded: center.isDegraded,
                    onSearch: { query in
                        searchResults = query.isEmpty ? nil : center.search(query)
                    },
                    onActivate: { event in center.markRead(ids: [event.id]) },
                    onMarkAllRead: { center.markAllRead(filter: .all) })
                    .frame(width: 660, height: 520)
            }
        }
    }

    /// Only sources that have actually produced something: a filter chip for a
    /// source with no events is a dead control.
    private var knownSources: [SignalSource] {
        var seen: [SignalSource] = []
        for event in center.recent where !seen.contains(event.source) {
            seen.append(event.source)
        }
        return seen
    }
}
