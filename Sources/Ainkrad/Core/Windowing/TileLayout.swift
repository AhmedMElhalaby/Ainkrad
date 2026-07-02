import Foundation
import Observation

/// One workspace's tile tree: opening an app fills an empty layout or
/// splits the focused Block (vertical, new Block second); closing a Block
/// promotes its sibling; the last close returns to the empty state. See
/// Window & Tile Management Architecture.md.
@Observable
final class TileLayout {
    private(set) var root: TileNode?
    private(set) var focusedBlockID: UUID?

    init() {}

    var isEmpty: Bool { root == nil }

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
    }

    func focus(_ id: UUID) {
        focusedBlockID = id
    }

    func setRatio(_ ratio: Double, for blockID: UUID) {
        guard let root else { return }
        self.root = Self.settingRatio(ratio, forLeafID: blockID, in: root)
    }

    // MARK: - Pure tree operations

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
