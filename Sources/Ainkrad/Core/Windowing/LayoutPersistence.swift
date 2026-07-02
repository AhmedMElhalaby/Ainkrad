import Foundation

/// A serializable pane tree. A node is a leaf (`appID` set) or a split
/// (`axis`/`fractions`/`children` set). Panel identity is NOT persisted —
/// restore mints fresh instances; running state (e.g. a terminal session)
/// is intentionally ephemeral.
struct PaneSnapshot: Codable, Equatable {
    var appID: String?
    var title: String?
    var axis: String?
    var fractions: [Double]?
    var children: [PaneSnapshot]?

    init?(node: PaneNode?) {
        guard let node else { return nil }
        switch node {
        case .leaf(let block):
            appID = block.appID
            title = block.title
        case .split(let axis, let children, let fractions):
            self.axis = axis == .horizontal ? "h" : "v"
            self.fractions = fractions
            self.children = children.compactMap { PaneSnapshot(node: $0) }
        }
    }

    func makeNode() -> PaneNode? {
        if let appID {
            return .leaf(Block(appID: appID, title: title))
        }
        guard let axis, let children, let fractions,
              children.count == fractions.count, !children.isEmpty else { return nil }
        let nodes = children.compactMap { $0.makeNode() }
        guard nodes.count == children.count else { return nil }
        if nodes.count == 1 { return nodes[0] }
        return .split(axis: axis == "h" ? .horizontal : .vertical, children: nodes, fractions: fractions)
    }
}

struct TabSnapshot: Codable, Equatable {
    var name: String
    var viewMode: TabViewMode
    var root: PaneSnapshot?
}

struct WorkspaceSnapshot: Codable, Equatable {
    var name: String
    var isMain: Bool
    var tabs: [TabSnapshot]
    var selectedTabIndex: Int
}

/// The whole persisted layout state, stored through SettingsStore and
/// restored at launch.
struct LayoutStateSnapshot: Codable, Equatable {
    static let storeKey = "workspace-layout-v1"

    var workspaces: [WorkspaceSnapshot]
    var activeWorkspaceIndex: Int
}

extension TileLayout {
    func snapshot() -> PaneSnapshot? {
        PaneSnapshot(node: root)
    }

    /// Replaces this layout's tree from a snapshot (persistence restore /
    /// tab duplication). Focus lands on the first pane.
    func apply(_ snapshot: PaneSnapshot) {
        replaceRoot(snapshot.makeNode())
    }
}

extension WorkspaceTab {
    func snapshot() -> TabSnapshot {
        TabSnapshot(name: name, viewMode: viewMode, root: tileLayout.snapshot())
    }
}

extension Workspace {
    func snapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            name: name,
            isMain: isMain,
            tabs: tabs.map { $0.snapshot() },
            selectedTabIndex: tabs.firstIndex(where: { $0.id == selectedTabID }) ?? 0
        )
    }
}
