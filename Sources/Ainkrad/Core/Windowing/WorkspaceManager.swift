import Foundation
import Observation

/// Multiple workspaces, each with its own independent tile layout. The
/// first workspace is the **main** one — the permanent home island (see
/// Workspace). Switching: `⌘1`-`⌘9` by position, `⌘⇧N` create, clickable
/// HUD diamonds, and the `⌥Tab` Workspace Overview. The whole layout
/// state persists as JSON through `SettingsStore` and restores at launch
/// (running panel state is ephemeral by design).
@MainActor
@Observable
final class WorkspaceManager {
    private(set) var workspaces: [Workspace]
    private(set) var activeWorkspaceID: UUID
    private var createdCount = 1
    /// Persistence hook, assigned at bootstrap and bubbled into every
    /// workspace's layout so any structural change saves.
    var onStateChange: (() -> Void)? {
        didSet {
            workspaces.forEach { $0.tileLayout.onStructuralChange = onStateChange }
        }
    }

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
        workspace.tileLayout.onStructuralChange = onStateChange
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        onStateChange?()
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
        onStateChange?()
    }

    func moveWorkspace(fromOffsets source: IndexSet, toOffset destination: Int) {
        workspaces.move(fromOffsets: source, toOffset: destination)
        onStateChange?()
    }

    func switchTo(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        activeWorkspaceID = id
        onStateChange?()
    }

    /// `index` is 0-based; `⌘1` maps to index 0, `⌘9` to index 8.
    func switchToWorkspace(at index: Int) {
        guard workspaces.indices.contains(index) else { return }
        activeWorkspaceID = workspaces[index].id
        onStateChange?()
    }

    /// Cycles to the next workspace in order, wrapping past the last back
    /// to the first (`⌘⌥→`). A no-op with a single workspace.
    func switchToNextWorkspace() { cycleActiveWorkspace(by: 1) }

    /// Cycles to the previous workspace in order, wrapping before the first
    /// around to the last (`⌘⌥←`). A no-op with a single workspace.
    func switchToPreviousWorkspace() { cycleActiveWorkspace(by: -1) }

    private func cycleActiveWorkspace(by delta: Int) {
        let count = workspaces.count
        guard count > 1,
              let current = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        let next = ((current + delta) % count + count) % count
        activeWorkspaceID = workspaces[next].id
        onStateChange?()
    }

    // MARK: - Persistence

    /// Explicit save trigger for mutations that don't flow through the
    /// structural-change hooks (e.g. renames, view-mode toggles).
    func persist() {
        onStateChange?()
    }

    func snapshot() -> LayoutStateSnapshot {
        LayoutStateSnapshot(
            workspaces: workspaces.map { $0.snapshot() },
            activeWorkspaceIndex: workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) ?? 0
        )
    }

    /// Rebuilds the whole state from a snapshot. The first main-flagged
    /// workspace becomes the home island; a missing main is re-created.
    func restore(from snapshot: LayoutStateSnapshot) {
        guard !snapshot.workspaces.isEmpty else { return }

        var restored: [Workspace] = []
        for workspaceSnapshot in snapshot.workspaces {
            let workspace = Workspace(
                name: workspaceSnapshot.name,
                isMain: workspaceSnapshot.isMain && !restored.contains(where: { $0.isMain }),
                viewMode: workspaceSnapshot.viewMode
            )
            workspace.tileLayout.onStructuralChange = onStateChange
            if let root = workspaceSnapshot.root {
                workspace.tileLayout.apply(root)
            }
            restored.append(workspace)
        }
        if !restored.contains(where: { $0.isMain }) {
            let main = Workspace(name: "Main", isMain: true)
            main.tileLayout.onStructuralChange = onStateChange
            restored.insert(main, at: 0)
        }

        workspaces = restored
        createdCount = max(restored.count, 1)
        let activeIndex = min(max(snapshot.activeWorkspaceIndex, 0), restored.count - 1)
        activeWorkspaceID = restored[activeIndex].id
    }
}
