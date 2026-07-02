import Testing
import Foundation
@testable import Ainkrad

@Suite("TileLayout (balanced grid)")
struct TileLayoutTests {

    // MARK: - Basics

    @Test("a new layout starts empty with no focused Block")
    func startsEmpty() {
        let layout = TileLayout()
        #expect(layout.isEmpty)
        #expect(layout.blocks.isEmpty)
        #expect(layout.focusedBlockID == nil)
    }

    @Test("opening apps appends panes in order and focuses the newest")
    func openAppendsInOrder() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        #expect(layout.blocks.map { $0.id } == [a.id, b.id, c.id])
        #expect(layout.appIDs == ["a", "b", "c"])
        #expect(layout.focusedBlockID == c.id)
    }

    @Test("multiple Blocks of the same app are allowed as distinct panes")
    func multipleBlocksOfSameAppAllowed() {
        let layout = TileLayout()
        let first = layout.openApp("terminal")
        let second = layout.openApp("terminal")

        #expect(first.id != second.id)
        #expect(layout.blocks.count == 2)
    }

    // MARK: - Balanced grid arrangement

    @Test("the grid stays balanced and near-square as panes are added")
    func gridShapePerCount() {
        let layout = TileLayout()

        layout.openApp("1")
        #expect(layout.grid.map { $0.count } == [1])

        layout.openApp("2")
        #expect(layout.grid.map { $0.count } == [2])

        layout.openApp("3")
        #expect(layout.grid.map { $0.count } == [2, 1])

        layout.openApp("4")
        #expect(layout.grid.map { $0.count } == [2, 2])

        layout.openApp("5")
        #expect(layout.grid.map { $0.count } == [3, 2])

        layout.openApp("6")
        #expect(layout.grid.map { $0.count } == [3, 3])

        layout.openApp("7")
        #expect(layout.grid.map { $0.count } == [3, 3, 1])

        layout.openApp("8")
        #expect(layout.grid.map { $0.count } == [3, 3, 2])

        layout.openApp("9")
        #expect(layout.grid.map { $0.count } == [3, 3, 3])
    }

    @Test("grid rows are filled in pane order, row-major")
    func gridFillsRowMajor() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        #expect(layout.grid[0].map { $0.id } == [a.id, b.id])
        #expect(layout.grid[1].map { $0.id } == [c.id])
    }

    @Test("row and column fractions are equalized whenever the pane count changes")
    func fractionsEqualizeOnStructureChange() {
        let layout = TileLayout()
        layout.openApp("a")
        layout.openApp("b")

        // Resize, then add a pane — fractions reset to equal.
        layout.setColumnBoundary(inRow: 0, after: 0, to: 0.8)
        #expect(layout.columnFractions[0][0] == 0.8)

        layout.openApp("c")

        #expect(layout.rowFractions == [0.5, 0.5])
        #expect(layout.columnFractions[0] == [0.5, 0.5])
        #expect(layout.columnFractions[1] == [1.0])
    }

    // MARK: - Close

    @Test("closing a pane reflows the grid and re-equalizes")
    func closeReflowsGrid() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        layout.close(a.id)

        #expect(layout.blocks.map { $0.id } == [b.id, c.id])
        #expect(layout.grid.map { $0.count } == [2])
        #expect(layout.columnFractions[0] == [0.5, 0.5])
    }

    @Test("closing the focused pane focuses its predecessor")
    func closingFocusedFocusesPredecessor() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")
        #expect(layout.focusedBlockID == c.id)

        layout.close(c.id)

        #expect(layout.focusedBlockID == b.id)
        _ = a
    }

    @Test("closing a non-focused pane keeps focus")
    func closingNonFocusedKeepsFocus() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        layout.focus(a.id)

        layout.close(b.id)

        #expect(layout.focusedBlockID == a.id)
    }

    @Test("closing the last pane returns to the empty state")
    func closingLastReturnsToEmpty() {
        let layout = TileLayout()
        let a = layout.openApp("a")

        layout.close(a.id)

        #expect(layout.isEmpty)
        #expect(layout.focusedBlockID == nil)
    }

    // MARK: - Reorder (drag a pane to change its position)

    @Test("movePane repositions a pane within the order")
    func movePaneRepositions() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        layout.movePane(c.id, before: a.id)

        #expect(layout.blocks.map { $0.id } == [c.id, a.id, b.id])
    }

    @Test("movePane to the end works via nil target")
    func movePaneToEnd() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        layout.movePane(a.id, before: nil)

        #expect(layout.blocks.map { $0.id } == [b.id, c.id, a.id])
    }

    @Test("movePane onto itself is a no-op")
    func movePaneOntoSelfIsNoOp() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")

        layout.movePane(a.id, before: a.id)

        #expect(layout.blocks.map { $0.id } == [a.id, b.id])
    }

    // MARK: - Resize boundaries

    @Test("setRowBoundary adjusts adjacent row fractions within limits")
    func setRowBoundaryAdjustsFractions() {
        let layout = TileLayout()
        layout.openApp("a")
        layout.openApp("b")
        layout.openApp("c") // 2 rows

        layout.setRowBoundary(after: 0, to: 0.7)
        #expect(abs(layout.rowFractions[0] - 0.7) < 0.0001)
        #expect(abs(layout.rowFractions[1] - 0.3) < 0.0001)

        // Clamped so no row collapses below 10%.
        layout.setRowBoundary(after: 0, to: 0.99)
        #expect(layout.rowFractions[0] <= 0.9)
    }

    @Test("setColumnBoundary adjusts adjacent column fractions in one row only")
    func setColumnBoundaryAdjustsOneRow() {
        let layout = TileLayout()
        layout.openApp("a")
        layout.openApp("b")
        layout.openApp("c")
        layout.openApp("d") // 2x2

        layout.setColumnBoundary(inRow: 0, after: 0, to: 0.65)

        #expect(abs(layout.columnFractions[0][0] - 0.65) < 0.0001)
        #expect(layout.columnFractions[1] == [0.5, 0.5])
    }

    // MARK: - Magnify

    @Test("toggleMagnify magnifies a pane and toggles back off")
    func toggleMagnifyTogglesOnAndOff() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        layout.openApp("b")

        layout.toggleMagnify(a.id)
        #expect(layout.magnifiedBlockID == a.id)

        layout.toggleMagnify(a.id)
        #expect(layout.magnifiedBlockID == nil)
    }

    @Test("closing the magnified pane clears magnification")
    func closingMagnifiedClearsMagnification() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        layout.openApp("b")
        layout.toggleMagnify(a.id)

        layout.close(a.id)

        #expect(layout.magnifiedBlockID == nil)
    }

    @Test("opening an app clears magnification")
    func openingAppClearsMagnification() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        layout.toggleMagnify(a.id)

        layout.openApp("b")

        #expect(layout.magnifiedBlockID == nil)
    }

    @Test("moving a pane clears magnification")
    func movingPaneClearsMagnification() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        layout.toggleMagnify(a.id)

        layout.movePane(a.id, before: nil)

        #expect(layout.magnifiedBlockID == nil)
        _ = b
    }
}
