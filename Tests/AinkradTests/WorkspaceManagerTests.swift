import Testing
import Foundation
@testable import Ainkrad

@Suite("WorkspaceManager")
@MainActor
struct WorkspaceManagerTests {

    @Test("starts with exactly one workspace, which is active")
    func startsWithOneActiveWorkspace() {
        let manager = WorkspaceManager()
        #expect(manager.workspaces.count == 1)
        #expect(manager.activeWorkspace.id == manager.workspaces[0].id)
    }

    @Test("createWorkspace adds a new workspace and switches to it")
    func createWorkspaceSwitchesToIt() {
        let manager = WorkspaceManager()
        let original = manager.activeWorkspace

        let created = manager.createWorkspace()

        #expect(manager.workspaces.count == 2)
        #expect(manager.activeWorkspace.id == created.id)
        #expect(created.id != original.id)
    }

    @Test("each workspace has its own independent TileLayout")
    func workspacesHaveIndependentLayouts() {
        let manager = WorkspaceManager()
        let first = manager.activeWorkspace
        first.tileLayout.openApp("terminal")

        let second = manager.createWorkspace()

        #expect(!first.tileLayout.isEmpty)
        #expect(second.tileLayout.isEmpty)
    }

    @Test("switchTo an existing workspace id makes it active")
    func switchToExistingWorkspace() {
        let manager = WorkspaceManager()
        let first = manager.activeWorkspace
        let second = manager.createWorkspace()

        manager.switchTo(first.id)

        #expect(manager.activeWorkspace.id == first.id)
        _ = second
    }

    @Test("switchTo a nonexistent id is a no-op")
    func switchToNonexistentIdIsNoOp() {
        let manager = WorkspaceManager()
        let active = manager.activeWorkspace

        manager.switchTo(UUID())

        #expect(manager.activeWorkspace.id == active.id)
    }

    @Test("switchToWorkspace(at:) jumps directly to the Nth workspace (⌘1-⌘9 mapping)")
    func switchToWorkspaceAtIndex() {
        let manager = WorkspaceManager()
        let first = manager.activeWorkspace
        let second = manager.createWorkspace()
        let third = manager.createWorkspace()

        manager.switchToWorkspace(at: 0)
        #expect(manager.activeWorkspace.id == first.id)

        manager.switchToWorkspace(at: 1)
        #expect(manager.activeWorkspace.id == second.id)

        manager.switchToWorkspace(at: 2)
        #expect(manager.activeWorkspace.id == third.id)
    }

    @Test("switchToWorkspace(at:) with an out-of-range index is a no-op")
    func switchToWorkspaceAtOutOfRangeIndexIsNoOp() {
        let manager = WorkspaceManager()
        let active = manager.activeWorkspace

        manager.switchToWorkspace(at: 8)

        #expect(manager.activeWorkspace.id == active.id)
    }
}
