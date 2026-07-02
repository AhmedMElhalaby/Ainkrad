import SwiftUI

/// Renders one workspace's tile tree, or the empty-state hint when it has
/// no open Blocks. See Window & Tile Management Architecture.md.
struct TileLayoutView: View {
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    var body: some View {
        if let root = tileLayout.root {
            TileNodeView(node: root, tileLayout: tileLayout, registry: registry)
        } else {
            EmptyWorkspaceView()
        }
    }
}

/// Recursively renders one node of the split tree: a Block for a leaf, or
/// two child nodes divided by a (possibly draggable) divider for a split.
struct TileNodeView: View {
    let node: TileNode
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    var body: some View {
        switch node {
        case .leaf(let block):
            BlockView(block: block, tileLayout: tileLayout, registry: registry)
        case .split(let axis, let ratio, let first, let second):
            SplitView(axis: axis, ratio: ratio, resizeAnchorID: resizeAnchorID(first: first, second: second), tileLayout: tileLayout) {
                TileNodeView(node: first, tileLayout: tileLayout, registry: registry)
            } second: {
                TileNodeView(node: second, tileLayout: tileLayout, registry: registry)
            }
        }
    }

    /// `TileLayout.setRatio` addresses a split by the id of an immediate
    /// leaf child, so only splits with at least one leaf child are
    /// resizable — a split of two nested sub-splits has no single Block id
    /// that maps back to it.
    private func resizeAnchorID(first: TileNode, second: TileNode) -> UUID? {
        if case .leaf(let block) = first { return block.id }
        if case .leaf(let block) = second { return block.id }
        return nil
    }
}
