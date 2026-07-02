import Foundation
import Observation

/// One workspace's pane layout, using the Termius split-view mechanism:
/// an ordered list of panes auto-arranged into a balanced, near-square
/// grid (row-major, last row stretches). New apps append at the end;
/// closing reflows; dragging a pane changes its position in the order;
/// row/column boundaries resize and re-equalize whenever the pane count
/// changes. One pane can be temporarily magnified to the full canvas.
@Observable
final class TileLayout {
    private(set) var blocks: [Block] = []
    private(set) var focusedBlockID: UUID?
    private(set) var magnifiedBlockID: UUID?
    /// Equal-by-default, user-resizable fractions; rebuilt on any change
    /// to the pane count.
    private(set) var rowFractions: [Double] = []
    private(set) var columnFractions: [[Double]] = []
    /// Transient drag context for pane reordering: set while a pane header
    /// drag session is live so drop targets can identify the source.
    var draggingBlockID: UUID?

    private static let minimumFraction = 0.1

    init() {}

    var isEmpty: Bool { blocks.isEmpty }

    /// Every open pane's app id, in pane order.
    var appIDs: [String] { blocks.map { $0.appID } }

    /// The balanced grid: rows of panes, row-major in pane order. Row
    /// count ≈ √n so the grid stays near-square; the last row may hold
    /// fewer panes and stretches to fill.
    var grid: [[Block]] {
        Self.arrange(blocks)
    }

    static func arrange(_ blocks: [Block]) -> [[Block]] {
        guard !blocks.isEmpty else { return [] }
        let count = blocks.count
        let rows = max(1, Int(Double(count).squareRoot().rounded()))
        let columns = Int((Double(count) / Double(rows)).rounded(.up))

        var result: [[Block]] = []
        var index = 0
        while index < count {
            let end = min(index + columns, count)
            result.append(Array(blocks[index..<end]))
            index = end
        }
        return result
    }

    @discardableResult
    func openApp(_ appID: String) -> Block {
        let block = Block(appID: appID)
        blocks.append(block)
        focusedBlockID = block.id
        magnifiedBlockID = nil
        equalizeFractions()
        return block
    }

    func close(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks.remove(at: index)
        if focusedBlockID == id {
            focusedBlockID = blocks.isEmpty ? nil : blocks[max(index - 1, 0)].id
        }
        if magnifiedBlockID == id {
            magnifiedBlockID = nil
        }
        equalizeFractions()
    }

    func focus(_ id: UUID) {
        focusedBlockID = id
    }

    /// Drag-to-reorder: repositions a pane before `targetID` (or at the
    /// end when nil). The grid shape is unchanged, so sizes are kept.
    func movePane(_ id: UUID, before targetID: UUID?) {
        guard id != targetID,
              let from = blocks.firstIndex(where: { $0.id == id }) else { return }
        let block = blocks.remove(at: from)
        if let targetID, let to = blocks.firstIndex(where: { $0.id == targetID }) {
            blocks.insert(block, at: to)
        } else {
            blocks.append(block)
        }
        magnifiedBlockID = nil
    }

    /// Temporarily zooms one pane to the full canvas (toggle). Structural
    /// changes (open/close/move) clear it.
    func toggleMagnify(_ id: UUID) {
        guard blocks.contains(where: { $0.id == id }) else { return }
        magnifiedBlockID = magnifiedBlockID == id ? nil : id
    }

    /// Drags the boundary under row `index` to cumulative `position`
    /// (0…1 of the canvas height); adjacent rows share the delta, and no
    /// row collapses below 10%.
    func setRowBoundary(after index: Int, to position: Double) {
        guard rowFractions.indices.contains(index), rowFractions.indices.contains(index + 1) else { return }
        let before = rowFractions.prefix(index).reduce(0, +)
        let pairSum = rowFractions[index] + rowFractions[index + 1]
        let newFirst = min(max(position - before, Self.minimumFraction), pairSum - Self.minimumFraction)
        rowFractions[index] = newFirst
        rowFractions[index + 1] = pairSum - newFirst
    }

    /// Drags the boundary after column `index` in `row` to cumulative
    /// `position` (0…1 of the row width) — other rows are unaffected.
    func setColumnBoundary(inRow row: Int, after index: Int, to position: Double) {
        guard columnFractions.indices.contains(row) else { return }
        var fractions = columnFractions[row]
        guard fractions.indices.contains(index), fractions.indices.contains(index + 1) else { return }
        let before = fractions.prefix(index).reduce(0, +)
        let pairSum = fractions[index] + fractions[index + 1]
        let newFirst = min(max(position - before, Self.minimumFraction), pairSum - Self.minimumFraction)
        fractions[index] = newFirst
        fractions[index + 1] = pairSum - newFirst
        columnFractions[row] = fractions
    }

    private func equalizeFractions() {
        let grid = self.grid
        rowFractions = Array(repeating: 1.0 / Double(max(grid.count, 1)), count: grid.count)
        columnFractions = grid.map { row in
            Array(repeating: 1.0 / Double(max(row.count, 1)), count: row.count)
        }
    }
}
