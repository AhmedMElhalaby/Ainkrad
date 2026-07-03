import Testing
import Foundation
@testable import Ainkrad

@Suite("Workspace persistence & Focus Mode")
@MainActor
struct LayoutPersistenceTests {

    @Test("toggling Focus Mode never touches the layout tree")
    func focusModePreservesLayout() {
        let workspace = Workspace(name: "W")
        _ = workspace.tileLayout.openApp("terminal")
        _ = workspace.tileLayout.openApp("settings")
        workspace.tileLayout.setBoundary(path: [], after: 0, to: 0.7)
        let before = workspace.tileLayout.snapshot()

        workspace.viewMode = .focus
        #expect(workspace.tileLayout.snapshot() == before)

        workspace.viewMode = .split
        #expect(workspace.tileLayout.snapshot() == before)
    }

    @Test("the manager's full state round-trips through JSON")
    func managerStateRoundTrips() throws {
        let manager = WorkspaceManager()
        let workspace = manager.createWorkspace()
        workspace.name = "Research"
        workspace.viewMode = .focus
        let a = workspace.tileLayout.openApp("terminal")
        _ = workspace.tileLayout.openApp("settings")
        let c = workspace.tileLayout.openApp("terminal")
        workspace.tileLayout.move(c.id, to: a.id, edge: .bottom)
        workspace.tileLayout.setBoundary(path: [], after: 0, to: 0.65)

        let data = try JSONEncoder().encode(manager.snapshot())
        let decoded = try JSONDecoder().decode(LayoutStateSnapshot.self, from: data)

        let restored = WorkspaceManager()
        restored.restore(from: decoded)

        #expect(restored.workspaces.count == 2)
        #expect(restored.workspaces[0].isMain)
        let restoredWorkspace = restored.workspaces[1]
        #expect(restoredWorkspace.name == "Research")
        #expect(restoredWorkspace.viewMode == .focus)
        #expect(restoredWorkspace.tileLayout.appIDs == workspace.tileLayout.appIDs)
        #expect(restoredWorkspace.tileLayout.snapshot() == workspace.tileLayout.snapshot())
        #expect(restored.activeWorkspace.name == "Research")
        #expect(restored.snapshot() == decoded)
    }

    @Test("restoring never yields a main-less state")
    func restoreRecreatesMissingMain() {
        let manager = WorkspaceManager()
        let snapshot = LayoutStateSnapshot(
            workspaces: [WorkspaceSnapshot(name: "Only", isMain: false, viewMode: .split, root: nil)],
            activeWorkspaceIndex: 0
        )

        manager.restore(from: snapshot)

        #expect(manager.workspaces.contains(where: { $0.isMain }))
    }

    @Test("structural changes trigger the persistence hook")
    func structuralChangesTriggerHook() {
        let manager = WorkspaceManager()
        var saves = 0
        manager.onStateChange = { saves += 1 }

        let workspace = manager.createWorkspace()
        let pane = workspace.tileLayout.openApp("terminal")
        workspace.tileLayout.split(pane.id, edge: .trailing)
        workspace.tileLayout.close(pane.id)

        #expect(saves >= 4)
    }
}
