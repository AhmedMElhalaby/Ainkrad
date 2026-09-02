import Foundation

/// One workspace's panes, as much as revealing needs to know.
struct SignalRevealWorkspace: Equatable {
    let id: UUID
    /// `(appID, blockID)` for every pane in this workspace, in layout order.
    let panes: [Pane]

    struct Pane: Equatable {
        let appID: String
        let blockID: UUID
        init(appID: String, blockID: UUID) {
            self.appID = appID
            self.blockID = blockID
        }
    }
}

/// What the host should do to show the app a notification came from.
enum SignalRevealAction: Equatable {
    /// The app is already on screen: focus its pane, switching workspace first
    /// when it lives on another one.
    case focus(workspaceID: UUID, blockID: UUID)
    /// The app presents as a floating overlay rather than a pane.
    case presentOverlay
    /// Not open anywhere — open it.
    case openNewPane
}

enum SignalReveal {
    /// Decides how to reveal `appID`.
    ///
    /// **Focusing an existing pane, not opening another one.** `openApp(_:)`
    /// unconditionally appends a new `Block`, so following a deep link through
    /// it gave the user a second, empty terminal instead of the session that
    /// called them — the notification took them further from the thing it was
    /// about.
    ///
    /// The active workspace is searched first: when a pane exists both here and
    /// elsewhere, yanking the user to another workspace would be a bigger
    /// disruption than the notification is worth.
    static func action(appID: String,
                       presentsAsOverlay: Bool,
                       workspaces: [SignalRevealWorkspace],
                       activeWorkspaceID: UUID) -> SignalRevealAction {
        if presentsAsOverlay { return .presentOverlay }

        if let active = workspaces.first(where: { $0.id == activeWorkspaceID }),
           let pane = active.panes.first(where: { $0.appID == appID }) {
            return .focus(workspaceID: active.id, blockID: pane.blockID)
        }
        for workspace in workspaces where workspace.id != activeWorkspaceID {
            if let pane = workspace.panes.first(where: { $0.appID == appID }) {
                return .focus(workspaceID: workspace.id, blockID: pane.blockID)
            }
        }
        return .openNewPane
    }
}
