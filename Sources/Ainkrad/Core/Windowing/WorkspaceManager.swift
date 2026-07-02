import Foundation
import Observation

/// Multiple workspaces, each with its own independent tile layout. The
/// first workspace is the **main** one — the permanent home island (see
/// Workspace). Switching: `⌘1`-`⌘9` by position, `⌘⇧N` create, clickable
/// HUD diamonds, and the `⌥Tab` Workspace Overview. Tile geometry is
/// session-only and never persisted.
@MainActor
@Observable
final class WorkspaceManager {
    private(set) var workspaces: [Workspace]
    private(set) var activeWorkspaceID: UUID
    private var createdCount = 1

    init() {
        let main = Workspace(name: "Main", isMain: true)
        self.workspaces = [main]
        self.activeWorkspaceID = main.id
    }

    var activeWorkspace: Workspace {
        workspaces.first(where: { $0.id == activeWorkspaceID })!
    }

    @discardableResult
    func createWorkspace() -> Workspace {
        createdCount += 1
        let workspace = Workspace(name: "Workspace \(createdCount)")
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        return workspace
    }

    /// The main workspace is permanent; deleting the active workspace
    /// falls back to main.
    func deleteWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }), !workspace.isMain else { return }
        workspaces.removeAll { $0.id == id }
        if activeWorkspaceID == id {
            activeWorkspaceID = workspaces.first(where: { $0.isMain })!.id
        }
    }

    func moveWorkspace(fromOffsets source: IndexSet, toOffset destination: Int) {
        workspaces.move(fromOffsets: source, toOffset: destination)
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
