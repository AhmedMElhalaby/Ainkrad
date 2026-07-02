import SwiftUI

/// Renders one workspace's tile tree, or the empty-state hint when it has
/// no open Blocks. See Window & Tile Management Architecture.md.
struct TileLayoutView: View {
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    var body: some View {
        if let root = tileLayout.root {
            // Breathing room around the floating Block panels — the sky
            // stays visible at the canvas edges.
            TileNodeView(node: root, tileLayout: tileLayout, registry: registry)
                .padding([.horizontal, .bottom], 10)
                .padding(.top, 4)
                .animation(.easeInOut(duration: 0.2), value: tileLayout.magnifiedBlockID)
        } else {
            EmptyWorkspaceView()
        }
    }
}

/// Recursively renders one node of the split tree: a Block for a leaf, or
/// two child nodes divided by an energy seam for a split. While a Block is
/// magnified, every split on its path collapses fully toward it — the
/// other side shrinks to zero but stays mounted, so sessions keep running.
struct TileNodeView: View {
    let node: TileNode
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    var body: some View {
        switch node {
        case .leaf(let block):
            BlockView(block: block, tileLayout: tileLayout, registry: registry)
        case .split(let axis, let ratio, let first, let second):
            let collapsedRatio: Double? = {
                guard tileLayout.magnifiedBlockID != nil else { return nil }
                if tileLayout.subtreeContainsMagnifiedBlock(first) { return 1.0 }
                if tileLayout.subtreeContainsMagnifiedBlock(second) { return 0.0 }
                return nil
            }()

            SplitView(
                axis: axis,
                ratio: collapsedRatio ?? ratio,
                isCollapsed: collapsedRatio != nil,
                resizeAnchorID: resizeAnchorID(first: first, second: second),
                tileLayout: tileLayout
            ) {
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
