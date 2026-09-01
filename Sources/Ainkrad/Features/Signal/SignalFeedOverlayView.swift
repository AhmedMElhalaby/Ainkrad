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

            SignalFeedIsland(
                events: events,
                unread: center.totalUnread,
                readIDs: [],
                knownSources: knownSources,
                isDegraded: center.isDegraded,
                onSearch: { query in
                    searchResults = query.isEmpty ? nil : center.search(query)
                },
                onActivate: { event in center.markRead(ids: [event.id]) },
                onMarkAllRead: { center.markAllRead(filter: .all) })
                .frame(width: 640, height: 520)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
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
