import Testing
import Foundation
@testable import Ainkrad

@Suite("Workspace tabs & persistence")
@MainActor
struct WorkspaceTabTests {

    // MARK: - Tab operations

    @Test("a workspace starts with one tab, selected")
    func startsWithOneTab() {
        let workspace = Workspace(name: "W")
        #expect(workspace.tabs.count == 1)
        #expect(workspace.tabs[0].name == "Tab 1")
        #expect(workspace.activeTab.id == workspace.tabs[0].id)
    }

    @Test("addTab appends, names sequentially, and selects the new tab")
    func addTabSelects() {
        let workspace = Workspace(name: "W")

        let second = workspace.addTab()

        #expect(workspace.tabs.count == 2)
        #expect(second.name == "Tab 2")
        #expect(workspace.activeTab.id == second.id)
    }

    @Test("closing the selected tab falls back to its predecessor")
    func closeSelectedFallsBack() {
        let workspace = Workspace(name: "W")
        let first = workspace.tabs[0]
        let second = workspace.addTab()

        workspace.closeTab(second.id)

        #expect(workspace.tabs.count == 1)
        #expect(workspace.activeTab.id == first.id)
    }

    @Test("the last tab cannot be closed")
    func lastTabCannotClose() {
        let workspace = Workspace(name: "W")

        workspace.closeTab(workspace.tabs[0].id)

        #expect(workspace.tabs.count == 1)
    }

    @Test("duplicateTab copies the layout shape with fresh panel instances")
    func duplicateTabCopiesLayout() {
        let workspace = Workspace(name: "W")
        let original = workspace.activeTab
        let a = original.tileLayout.openApp("terminal")
        _ = original.tileLayout.openApp("settings")

        let copy = workspace.duplicateTab(original.id)

        #expect(copy?.tileLayout.appIDs == ["terminal", "settings"])
        #expect(copy?.tileLayout.blocks.first?.id != a.id)
        #expect(workspace.activeTab.id == copy?.id)
    }

    @Test("moveTab reorders and selectTab(at:) follows the new order")
    func moveTabReorders() {
        let workspace = Workspace(name: "W")
        let first = workspace.tabs[0]
        let second = workspace.addTab()

        workspace.moveTab(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        #expect(workspace.tabs.map { $0.id } == [second.id, first.id])
        workspace.selectTab(at: 1)
        #expect(workspace.activeTab.id == first.id)
    }

    @Test("movePanel transplants a running panel between tabs")
    func movePanelBetweenTabs() {
        let workspace = Workspace(name: "W")
        let source = workspace.activeTab
        _ = source.tileLayout.openApp("terminal")
        let moving = source.tileLayout.openApp("settings")
        let destination = workspace.addTab()

        workspace.movePanel(moving.id, from: source, to: destination)

        #expect(source.tileLayout.appIDs == ["terminal"])
        #expect(destination.tileLayout.blocks.contains(where: { $0.id == moving.id }))
        #expect(workspace.activeTab.id == destination.id)
    }

    // MARK: - Focus Mode

    @Test("toggling Focus Mode never touches the layout tree")
    func focusModePreservesLayout() {
        let workspace = Workspace(name: "W")
        let tab = workspace.activeTab
        _ = tab.tileLayout.openApp("terminal")
        _ = tab.tileLayout.openApp("settings")
        tab.tileLayout.setBoundary(path: [], after: 0, to: 0.7)
        let before = tab.tileLayout.snapshot()

        tab.viewMode = .focus
        #expect(tab.tileLayout.snapshot() == before)

        tab.viewMode = .split
        #expect(tab.tileLayout.snapshot() == before)
    }

    // MARK: - Whole-state persistence

    @Test("the manager's full state round-trips through JSON")
    func managerStateRoundTrips() throws {
        let manager = WorkspaceManager()
        let workspace = manager.createWorkspace()
        workspace.name = "Research"
        _ = workspace.activeTab.tileLayout.openApp("terminal")
        let tab2 = workspace.addTab()
        tab2.name = "Monitoring"
        tab2.viewMode = .focus
        _ = tab2.tileLayout.openApp("settings")

        let data = try JSONEncoder().encode(manager.snapshot())
        let decoded = try JSONDecoder().decode(LayoutStateSnapshot.self, from: data)

        let restored = WorkspaceManager()
        restored.restore(from: decoded)

        #expect(restored.workspaces.count == 2)
        #expect(restored.workspaces[0].isMain)
        let restoredWorkspace = restored.workspaces[1]
        #expect(restoredWorkspace.name == "Research")
        #expect(restoredWorkspace.tabs.count == 2)
        #expect(restoredWorkspace.tabs[0].tileLayout.appIDs == ["terminal"])
        #expect(restoredWorkspace.tabs[1].name == "Monitoring")
        #expect(restoredWorkspace.tabs[1].viewMode == .focus)
        #expect(restoredWorkspace.tabs[1].tileLayout.appIDs == ["settings"])
        #expect(restored.activeWorkspace.name == "Research")
        #expect(restoredWorkspace.activeTab.id == restoredWorkspace.tabs[1].id)
        #expect(restored.snapshot() == decoded)
    }
}
