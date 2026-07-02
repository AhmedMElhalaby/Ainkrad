import Foundation
import Observation

/// A container's layout direction: `.horizontal` lays children out as
/// side-by-side columns, `.vertical` stacks them as rows.
enum PaneAxis: Equatable {
    case horizontal
    case vertical
}

/// Which edge of a target pane a dragged pane is dropped on.
enum PaneEdge {
    case leading, trailing, top, bottom

    var axis: PaneAxis {
        switch self {
        case .leading, .trailing: return .horizontal
        case .top, .bottom: return .vertical
        }
    }

    /// Whether the dropped pane lands before the target.
    var insertsFirst: Bool {
        self == .leading || self == .top
    }
}

/// The N-ary split tree (the Termius split-view structure): a node is a
/// pane, or a container of 2+ children sharing one direction with
/// per-child fractions. Siblings in the same direction live flat in ONE
/// container — three columns are one horizontal split at ⅓ each, never
/// nested binary halves.
indirect enum PaneNode: Equatable {
    case leaf(Block)
    case split(axis: PaneAxis, children: [PaneNode], fractions: [Double])
}

/// One workspace's pane layout, copying the Termius split-view mechanism
/// observed from the reference recording:
///
/// - Opening an app appends an equal top-level column.
/// - Dropping a pane on a target's edge *parallel* to the target's
///   container joins that container as an equal sibling (3 panes → equal
///   thirds); a *perpendicular* drop wraps the target into a new 50/50
///   container.
/// - Closing/moving out re-equalizes the affected container and collapses
///   single-child containers.
/// - Sibling boundaries resize (10% minimum); one pane can be temporarily
///   magnified to the full canvas.
@Observable
final class TileLayout {
    private(set) var root: PaneNode?
    private(set) var focusedBlockID: UUID?
    private(set) var magnifiedBlockID: UUID?
    /// Transient drag context: set while a pane header drag session is
    /// live so drop targets can identify the source.
    var draggingBlockID: UUID?

    private static let minimumFraction = 0.1

    init() {}

    var isEmpty: Bool { root == nil }

    /// Every open pane, in tree (reading) order.
    var blocks: [Block] {
        root.map(Self.collectBlocks) ?? []
    }

    var appIDs: [String] { blocks.map { $0.appID } }

    // MARK: - Operations

    @discardableResult
    func openApp(_ appID: String) -> Block {
        let block = Block(appID: appID)

        switch root {
        case nil:
            root = .leaf(block)
        case .leaf(let existing):
            root = .split(axis: .horizontal, children: [.leaf(existing), .leaf(block)], fractions: Self.equalFractions(2))
        case .split(.horizontal, var children, _):
            children.append(.leaf(block))
            root = .split(axis: .horizontal, children: children, fractions: Self.equalFractions(children.count))
        case .split(let axis, let children, let fractions):
            // Root stacks vertically: wrap it beside the new column.
            root = .split(
                axis: .horizontal,
                children: [.split(axis: axis, children: children, fractions: fractions), .leaf(block)],
                fractions: Self.equalFractions(2)
            )
        }

        focusedBlockID = block.id
        magnifiedBlockID = nil
        return block
    }

    func close(_ id: UUID) {
        guard let root else { return }
        let paneOrder = blocks
        guard let index = paneOrder.firstIndex(where: { $0.id == id }) else { return }

        self.root = Self.removing(id, from: root)

        if focusedBlockID == id {
            let survivors = blocks
            focusedBlockID = survivors.isEmpty ? nil : survivors[min(max(index - 1, 0), survivors.count - 1)].id
        }
        if magnifiedBlockID == id {
            magnifiedBlockID = nil
        }
    }

    func focus(_ id: UUID) {
        focusedBlockID = id
    }

    /// Drag-to-rearrange: removes the pane from its slot and re-inserts it
    /// on the target's edge — joining the target's container as an equal
    /// sibling when the edge is parallel to it, or wrapping the target
    /// into a new 50/50 container when perpendicular.
    func move(_ id: UUID, to targetID: UUID, edge: PaneEdge) {
        guard id != targetID, let root else { return }
        guard let block = blocks.first(where: { $0.id == id }),
              blocks.contains(where: { $0.id == targetID }) else { return }

        guard let remaining = Self.removing(id, from: root) else { return }
        guard Self.collectBlocks(remaining).contains(where: { $0.id == targetID }) else { return }

        self.root = Self.inserting(block, at: targetID, edge: edge, in: remaining)
        focusedBlockID = id
        magnifiedBlockID = nil
    }

    /// Temporarily zooms one pane to the full canvas (toggle). Structural
    /// changes (open/close/move) clear it.
    func toggleMagnify(_ id: UUID) {
        guard blocks.contains(where: { $0.id == id }) else { return }
        magnifiedBlockID = magnifiedBlockID == id ? nil : id
    }

    /// Drags the boundary after child `index` of the container at `path`
    /// (child indices from the root) to cumulative `position` (0…1 of that
    /// container's extent). Adjacent siblings share the delta; no sibling
    /// collapses below 10%.
    func setBoundary(path: [Int], after index: Int, to position: Double) {
        guard let root else { return }
        self.root = Self.settingBoundary(path: ArraySlice(path), after: index, to: position, in: root)
    }

    /// Whether `node` contains the magnified pane — the rendering layer
    /// collapses every sibling outside its path.
    func subtreeContainsMagnifiedBlock(_ node: PaneNode) -> Bool {
        guard let magnifiedBlockID else { return false }
        return Self.collectBlocks(node).contains(where: { $0.id == magnifiedBlockID })
    }

    // MARK: - Pure tree operations

    private static func equalFractions(_ count: Int) -> [Double] {
        Array(repeating: 1.0 / Double(max(count, 1)), count: count)
    }

    private static func collectBlocks(_ node: PaneNode) -> [Block] {
        switch node {
        case .leaf(let block):
            return [block]
        case .split(_, let children, _):
            return children.flatMap(collectBlocks)
        }
    }

    /// Removes the pane, re-equalizing the container it left and
    /// collapsing containers reduced to one child. Returns nil when the
    /// tree becomes empty.
    private static func removing(_ id: UUID, from node: PaneNode) -> PaneNode? {
        switch node {
        case .leaf(let block):
            return block.id == id ? nil : node
        case .split(let axis, let children, let fractions):
            var newChildren: [PaneNode] = []
            var removedDirectChild = false

            for (child, fraction) in zip(children, fractions) {
                if case .leaf(let block) = child, block.id == id {
                    removedDirectChild = true
                    continue
                }
                if let kept = removing(id, from: child) {
                    newChildren.append(kept)
                } else {
                    removedDirectChild = true
                }
                _ = fraction
            }

            if newChildren.isEmpty { return nil }
            if newChildren.count == 1 { return newChildren[0] }

            if removedDirectChild {
                return .split(axis: axis, children: newChildren, fractions: equalFractions(newChildren.count))
            }
            // Removal happened deeper; child count here is unchanged, so
            // keep this container's fractions.
            return .split(axis: axis, children: newChildren, fractions: node.fractionsOrEqual(count: newChildren.count))
        }
    }

    private static func inserting(_ block: Block, at targetID: UUID, edge: PaneEdge, in node: PaneNode) -> PaneNode {
        switch node {
        case .leaf(let existing):
            guard existing.id == targetID else { return node }
            let pair = edge.insertsFirst
                ? [PaneNode.leaf(block), node]
                : [node, PaneNode.leaf(block)]
            return .split(axis: edge.axis, children: pair, fractions: equalFractions(2))

        case .split(let axis, let children, let fractions):
            // Parallel drop onto a direct child: join this container as an
            // equal sibling instead of nesting.
            if axis == edge.axis,
               let targetIndex = children.firstIndex(where: { if case .leaf(let b) = $0 { b.id == targetID } else { false } }) {
                var newChildren = children
                newChildren.insert(.leaf(block), at: edge.insertsFirst ? targetIndex : targetIndex + 1)
                return .split(axis: axis, children: newChildren, fractions: equalFractions(newChildren.count))
            }

            return .split(
                axis: axis,
                children: children.map { inserting(block, at: targetID, edge: edge, in: $0) },
                fractions: fractions
            )
        }
    }

    private static func settingBoundary(path: ArraySlice<Int>, after index: Int, to position: Double, in node: PaneNode) -> PaneNode {
        guard case .split(let axis, let children, var fractions) = node else { return node }

        if let step = path.first {
            guard children.indices.contains(step) else { return node }
            var newChildren = children
            newChildren[step] = settingBoundary(path: path.dropFirst(), after: index, to: position, in: children[step])
            return .split(axis: axis, children: newChildren, fractions: fractions)
        }

        guard fractions.indices.contains(index), fractions.indices.contains(index + 1) else { return node }
        let before = fractions.prefix(index).reduce(0, +)
        let pairSum = fractions[index] + fractions[index + 1]
        let newFirst = min(max(position - before, minimumFraction), pairSum - minimumFraction)
        fractions[index] = newFirst
        fractions[index + 1] = pairSum - newFirst
        return .split(axis: axis, children: children, fractions: fractions)
    }
}

private extension PaneNode {
    func fractionsOrEqual(count: Int) -> [Double] {
        if case .split(_, _, let fractions) = self, fractions.count == count {
            return fractions
        }
        return Array(repeating: 1.0 / Double(max(count, 1)), count: count)
    }
}
