import Foundation
import Observation

/// Tracks every open Files pane and answers "which pane is the other one?" for
/// cross-pane copy and move.
///
/// Lives in `AppEnvironment`, NOT inside a pane. Panes are created and
/// destroyed by the host's tiling, so cross-pane state cannot live in a
/// participant — closing the pane you were copying *from* would take the
/// coordination with it.
///
/// This is also why Files is a single-pane app: the host already tiles, so a
/// second Files pane IS the second pane, rather than an internal split
/// fighting the window manager.
@MainActor
@Observable
final class PaneCoordinator {
    private struct Pane {
        let token: UUID
        let store: FilesPaneStore
    }

    private var panes: [Pane] = []
    /// Most-recently-focused last. Only consulted when three or more panes are
    /// open, where "the other pane" is otherwise ambiguous.
    private var focusOrder: [UUID] = []

    var paneCount: Int { panes.count }

    func register(_ store: FilesPaneStore) -> UUID {
        let token = UUID()
        panes.append(Pane(token: token, store: store))
        focusOrder.append(token)
        return token
    }

    func deregister(_ token: UUID) {
        panes.removeAll { $0.token == token }
        focusOrder.removeAll { $0 == token }
    }

    func noteFocus(_ token: UUID) {
        guard panes.contains(where: { $0.token == token }) else { return }
        focusOrder.removeAll { $0 == token }
        focusOrder.append(token)
    }

    /// The destination pane for an operation initiated from `token`:
    ///
    /// - exactly two panes → the other one, unambiguously
    /// - three or more → the most-recently-focused pane that isn't the caller
    /// - one → `nil`, and the caller prompts for a destination instead
    func otherPane(than token: UUID) -> FilesPaneStore? {
        let others = panes.filter { $0.token != token }
        guard !others.isEmpty else { return nil }
        if others.count == 1 { return others[0].store }

        // Walk the focus order from most recent, skipping the caller.
        for candidate in focusOrder.reversed() where candidate != token {
            if let pane = others.first(where: { $0.token == candidate }) {
                return pane.store
            }
        }
        return others.last?.store
    }
}
