import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Hosts `SignalFeedIsland` as a dismissible overlay, matching the other HUD
/// overlays (scrim tap to dismiss, fade transition, no separator chrome).
struct SignalFeedOverlayView: View {
    let center: SignalCenter
    /// Passed in rather than read from `AppEnvironment`: a view that reaches for
    /// the whole environment cannot be rendered without one, which broke the
    /// snapshot suite the moment action routing was added — and broke it by
    /// CRASHING the test runner, so the run reported "passed" for the handful of
    /// tests that had already finished.
    var hub: SignalEmitterHub?
    let onDismiss: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @State private var searchResults: [SignalEvent]?
    @State private var pendingDestructive: (SignalEvent, SignalAction)?

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
                    onAction: { event, action in
                        guard let hub else { return }
                        if let needsConfirmation = SignalActionRouter(hub: hub).invoke(event, action) {
                            pendingDestructive = (event, needsConfirmation)
                        }
                    },
                    onMarkAllRead: { center.markAllRead(filter: .all) })
                    .frame(width: 660, height: 520)
            }
        }
        .confirmationDialog(
            pendingDestructive.map { "\($0.1.label)?" } ?? "",
            isPresented: Binding(get: { pendingDestructive != nil },
                                 set: { if !$0 { pendingDestructive = nil } }),
            titleVisibility: .visible
        ) {
            if let (event, action) = pendingDestructive {
                Button(action.label, role: .destructive) {
                    if let hub { SignalActionRouter(hub: hub).dispatch(event, action) }
                    pendingDestructive = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDestructive = nil }
        } message: {
            Text("This action was published by the app and cannot be undone from here.")
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
