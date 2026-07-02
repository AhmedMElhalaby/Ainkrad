import Foundation
import Observation

/// Which edge of a target Block a dragged Block is dropped on — decides
/// the split axis and order for drag-to-rearrange.
enum BlockDropEdge {
    case leading, trailing, top, bottom

    var axis: SplitAxis {
        switch self {
        case .leading, .trailing: return .vertical
        case .top, .bottom: return .horizontal
        }
    }

    /// Whether the moved Block lands before the target in the new split.
    var insertsFirst: Bool {
        self == .leading || self == .top
    }
}

/// One workspace's tile tree: opening an app fills an empty layout or
/// splits the focused Block (vertical, new Block second); closing a Block
/// promotes its sibling; the last close returns to the empty state.
/// Blocks can be moved onto another Block's edge (drag-to-rearrange) and
/// temporarily magnified to fill the canvas. See Window & Tile Management
/// Architecture.md.
@Observable
final class TileLayout {
    private(set) var root: TileNode?
    private(set) var focusedBlockID: UUID?
    private(set) var magnifiedBlockID: UUID?
    /// Transient drag context for drag-to-rearrange: set while a Block
    /// header drag session is live so drop targets can identify the source.
    var draggingBlockID: UUID?

    init() {}

    var isEmpty: Bool { root == nil }

    /// Every open Block's app id, in leaf order — the Workspace Overview's
    /// "what's inside" summary.
    var appIDs: [String] {
        root.map(Self.collectAppIDs) ?? []
    }

    @discardableResult
    func openApp(_ appID: String) -> Block {
        let newBlock = Block(appID: appID)

        if let root, let focusedBlockID {
            self.root = Self.replacing(root, leafID: focusedBlockID) { existingBlock in
                .split(axis: .vertical, ratio: 0.5, first: .leaf(existingBlock), second: .leaf(newBlock))
            }
        } else {
            root = .leaf(newBlock)
        }

        focusedBlockID = newBlock.id
        magnifiedBlockID = nil
        return newBlock
    }

    func close(_ id: UUID) {
        guard let root else { return }
        let result = Self.removing(id, from: root)
        guard result.found else { return }

        self.root = result.node
        if focusedBlockID == id {
            focusedBlockID = self.root.map(Self.firstLeafID)
        }
        if magnifiedBlockID == id {
            magnifiedBlockID = nil
        }
    }

    func focus(_ id: UUID) {
        focusedBlockID = id
    }

    func setRatio(_ ratio: Double, for blockID: UUID) {
        guard let root else { return }
        self.root = Self.settingRatio(ratio, forLeafID: blockID, in: root)
    }

    /// Drag-to-rearrange: removes the Block from its slot (sibling
    /// promotes) and re-splits it onto the target Block's given edge. The
    /// moved Block keeps focus; any magnification is cleared.
    func move(_ id: UUID, to targetID: UUID, edge: BlockDropEdge) {
        guard id != targetID, let root else { return }
        guard let block = Self.firstBlock(withID: id, in: root) else { return }

        let removal = Self.removing(id, from: root)
        guard removal.found, let remaining = removal.node,
              Self.containsBlock(targetID, in: remaining) else { return }

        self.root = Self.replacing(remaining, leafID: targetID) { targetBlock in
            edge.insertsFirst
                ? .split(axis: edge.axis, ratio: 0.5, first: .leaf(block), second: .leaf(targetBlock))
                : .split(axis: edge.axis, ratio: 0.5, first: .leaf(targetBlock), second: .leaf(block))
        }
        focusedBlockID = id
        magnifiedBlockID = nil
    }

    /// Temporarily zooms one Block to the full canvas (toggle). Structural
    /// changes (open/close/move) clear it.
    func toggleMagnify(_ id: UUID) {
        guard let root, Self.containsBlock(id, in: root) else { return }
        magnifiedBlockID = magnifiedBlockID == id ? nil : id
    }

    /// Whether `node` contains the magnified Block — the rendering layer
    /// uses this to collapse the other side of each split.
    func subtreeContainsMagnifiedBlock(_ node: TileNode) -> Bool {
        guard let magnifiedBlockID else { return false }
        return Self.containsBlock(magnifiedBlockID, in: node)
    }

    // MARK: - Pure tree operations

    private static func collectAppIDs(in node: TileNode) -> [String] {
        switch node {
        case .leaf(let block):
            return [block.appID]
        case .split(_, _, let first, let second):
            return collectAppIDs(in: first) + collectAppIDs(in: second)
        }
    }

    private static func replacing(_ node: TileNode, leafID: UUID, with replacement: (Block) -> TileNode) -> TileNode {
        switch node {
        case .leaf(let block):
            return block.id == leafID ? replacement(block) : node
        case .split(let axis, let ratio, let first, let second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: replacing(first, leafID: leafID, with: replacement),
                second: replacing(second, leafID: leafID, with: replacement)
            )
        }
    }

    private static func removing(_ id: UUID, from node: TileNode) -> (node: TileNode?, found: Bool) {
        switch node {
        case .leaf(let block):
            return block.id == id ? (nil, true) : (node, false)
        case .split(let axis, let ratio, let first, let second):
            let firstResult = removing(id, from: first)
            if firstResult.found {
                guard let newFirst = firstResult.node else { return (second, true) }
                return (.split(axis: axis, ratio: ratio, first: newFirst, second: second), true)
            }
            let secondResult = removing(id, from: second)
            if secondResult.found {
                guard let newSecond = secondResult.node else { return (first, true) }
                return (.split(axis: axis, ratio: ratio, first: first, second: newSecond), true)
            }
            return (node, false)
        }
    }

    private static func firstLeafID(in node: TileNode) -> UUID {
        switch node {
        case .leaf(let block): return block.id
        case .split(_, _, let first, _): return firstLeafID(in: first)
        }
    }

    private static func firstBlock(withID id: UUID, in node: TileNode) -> Block? {
        switch node {
        case .leaf(let block):
            return block.id == id ? block : nil
        case .split(_, _, let first, let second):
            return firstBlock(withID: id, in: first) ?? firstBlock(withID: id, in: second)
        }
    }

    private static func containsBlock(_ id: UUID, in node: TileNode) -> Bool {
        firstBlock(withID: id, in: node) != nil
    }

    private static func settingRatio(_ ratio: Double, forLeafID id: UUID, in node: TileNode) -> TileNode {
        switch node {
        case .leaf:
            return node
        case .split(let axis, let currentRatio, let first, let second):
            if case .leaf(let block) = first, block.id == id {
                return .split(axis: axis, ratio: ratio, first: first, second: second)
            }
            if case .leaf(let block) = second, block.id == id {
                return .split(axis: axis, ratio: ratio, first: first, second: second)
            }
            return .split(
                axis: axis,
                ratio: currentRatio,
                first: settingRatio(ratio, forLeafID: id, in: first),
                second: settingRatio(ratio, forLeafID: id, in: second)
            )
        }
    }
}
