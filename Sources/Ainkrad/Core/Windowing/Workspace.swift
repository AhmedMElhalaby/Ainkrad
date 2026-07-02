import Foundation
import Observation

/// One workspace: an identity, a user-editable name, and its tabs — each
/// tab holding an independent layout tree. Exactly one workspace is the
/// **main** one — the home island: it stays empty, and opening an app from
/// it spawns a new workspace instead (see LauncherStore). It can never be
/// deleted.
@Observable
final class Workspace: Identifiable {
    let id: UUID
    let isMain: Bool
    var name: String
    private(set) var tabs: [WorkspaceTab]
    private(set) var selectedTabID: UUID
    private var createdTabCount = 1
    /// Bubbled to WorkspaceManager for persistence.
    var onStructuralChange: (() -> Void)? {
        didSet { tabs.forEach { $0.tileLayout.onStructuralChange = onStructuralChange } }
    }

    init(id: UUID = UUID(), name: String, isMain: Bool = false) {
        self.id = id
        self.name = name
        self.isMain = isMain
        let firstTab = WorkspaceTab(name: "Tab 1")
        self.tabs = [firstTab]
        self.selectedTabID = firstTab.id
    }

    var activeTab: WorkspaceTab {
        tabs.first(where: { $0.id == selectedTabID }) ?? tabs[0]
    }

    /// Every open panel's app id across all tabs (Workspace Overview
    /// summary).
    var appIDs: [String] {
        tabs.flatMap { $0.tileLayout.appIDs }
    }

    // MARK: - Tab operations

    @discardableResult
    func addTab() -> WorkspaceTab {
        createdTabCount += 1
        let tab = WorkspaceTab(name: "Tab \(createdTabCount)")
        tab.tileLayout.onStructuralChange = onStructuralChange
        tabs.append(tab)
        selectedTabID = tab.id
        onStructuralChange?()
        return tab
    }

    /// The last tab can't be closed — close the workspace instead.
    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[max(index - 1, 0)].id
        }
        onStructuralChange?()
    }

    /// Duplicates a tab's layout shape with fresh panel instances.
    @discardableResult
    func duplicateTab(_ id: UUID) -> WorkspaceTab? {
        guard let source = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let original = tabs[source]
        let copy = WorkspaceTab(name: original.name + " Copy", viewMode: original.viewMode)
        copy.tileLayout.onStructuralChange = onStructuralChange
        if let snapshot = PaneSnapshot(node: original.tileLayout.root) {
            copy.tileLayout.apply(snapshot)
        }
        tabs.insert(copy, at: source + 1)
        selectedTabID = copy.id
        onStructuralChange?()
        return copy
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        onStructuralChange?()
    }

    /// `index` is 0-based; ⌘1 maps to index 0.
    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTabID = tabs[index].id
        onStructuralChange?()
    }

    func moveTab(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        onStructuralChange?()
    }

    /// Moves a panel from one tab's layout into another's (as a new equal
    /// column there), switching to the destination tab.
    func movePanel(_ blockID: UUID, from sourceTab: WorkspaceTab, to destinationTab: WorkspaceTab) {
        guard sourceTab.id != destinationTab.id,
              let block = sourceTab.tileLayout.extract(blockID) else { return }
        destinationTab.tileLayout.attach(block)
        selectedTabID = destinationTab.id
        onStructuralChange?()
    }

    // MARK: - Restore

    /// Rebuilds tabs from a snapshot (persistence restore).
    func restoreTabs(_ snapshots: [TabSnapshot], selectedIndex: Int) {
        guard !snapshots.isEmpty else { return }
        tabs = snapshots.map { snapshot in
            let tab = WorkspaceTab(name: snapshot.name, viewMode: snapshot.viewMode)
            tab.tileLayout.onStructuralChange = onStructuralChange
            if let root = snapshot.root {
                tab.tileLayout.apply(root)
            }
            return tab
        }
        createdTabCount = max(tabs.count, 1)
        selectedTabID = tabs[min(max(selectedIndex, 0), tabs.count - 1)].id
    }
}
