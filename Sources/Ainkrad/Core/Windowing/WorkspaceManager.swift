import Foundation
import Observation

/// Multiple workspaces, each with its own independent tile layout.
/// Switching is keyboard-only (`⌘1`-`⌘9`, `⌘⇧N`) — see
/// ADR-0008 App Launcher & Workspace Switching. Tile geometry is
/// session-only and never persisted; only one workspace exists at launch.
@MainActor
@Observable
final class WorkspaceManager {
    private(set) var workspaces: [Workspace]
    private(set) var activeWorkspaceID: UUID

    init() {
        let first = Workspace()
        self.workspaces = [first]
        self.activeWorkspaceID = first.id
    }

    var activeWorkspace: Workspace {
        workspaces.first(where: { $0.id == activeWorkspaceID })!
    }

    @discardableResult
    func createWorkspace() -> Workspace {
        let workspace = Workspace()
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        return workspace
    }

    func switchTo(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        activeWorkspaceID = id
    }

    /// `index` is 0-based; `⌘1` maps to index 0, `⌘9` to index 8.
    func switchToWorkspace(at index: Int) {
        guard workspaces.indices.contains(index) else { return }
        activeWorkspaceID = workspaces[index].id
    }
}
