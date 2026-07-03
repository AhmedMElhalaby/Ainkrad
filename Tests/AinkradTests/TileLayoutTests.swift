import Testing
import Foundation
@testable import Ainkrad

@Suite("TileLayout (N-ary split tree)")
struct TileLayoutTests {

    // MARK: - Basics

    @Test("a new layout starts empty with no focused pane")
    func startsEmpty() {
        let layout = TileLayout()
        #expect(layout.isEmpty)
        #expect(layout.blocks.isEmpty)
        #expect(layout.focusedBlockID == nil)
    }

    @Test("opening apps appends equal top-level columns, newest focused")
    func openAppendsEqualColumns() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        guard case .split(let axis, let children, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(axis == .horizontal)
        #expect(children == [.leaf(a), .leaf(b), .leaf(c)])
        #expect(fractions.count == 3)
        #expect(abs(fractions[0] - 1.0 / 3.0) < 0.0001)
        #expect(layout.focusedBlockID == c.id)
        #expect(layout.appIDs == ["a", "b", "c"])
    }

    @Test("a single pane fills the canvas")
    func singlePaneIsRootLeaf() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        #expect(layout.root == .leaf(a))
    }

    // MARK: - Close

    @Test("closing a pane re-equalizes its siblings")
    func closeReEqualizesSiblings() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        layout.close(b.id)

        guard case .split(_, let children, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(children == [.leaf(a), .leaf(c)])
        #expect(fractions == [0.5, 0.5])
    }

    @Test("a container left with one child collapses into it")
    func singleChildContainerCollapses() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        // Stack b under a: root becomes a single vertical container.
        layout.move(b.id, to: a.id, edge: .bottom)

        layout.close(b.id)

        #expect(layout.root == .leaf(a))
    }

    @Test("closing the focused pane focuses its predecessor in pane order")
    func closingFocusedFocusesPredecessor() {
        let layout = TileLayout()
        _ = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        layout.close(c.id)

        #expect(layout.focusedBlockID == b.id)
    }

    @Test("closing the last pane returns to the empty state")
    func closingLastReturnsToEmpty() {
        let layout = TileLayout()
        let a = layout.openApp("a")

        layout.close(a.id)

        #expect(layout.isEmpty)
        #expect(layout.focusedBlockID == nil)
    }

    // MARK: - Move: parallel drops join the container as an equal sibling

    @Test("dropping on a side edge inserts as an equal sibling column")
    func parallelDropInsertsSibling() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        // Drag c onto a's leading edge: [c, a, b] as equal thirds.
        layout.move(c.id, to: a.id, edge: .leading)

        guard case .split(let axis, let children, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(axis == .horizontal)
        #expect(children == [.leaf(c), .leaf(a), .leaf(b)])
        #expect(abs(fractions[0] - 1.0 / 3.0) < 0.0001)
        #expect(layout.focusedBlockID == c.id)
    }

    @Test("dropping on a trailing edge lands after the target")
    func trailingDropLandsAfterTarget() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        layout.move(a.id, to: b.id, edge: .trailing)

        guard case .split(_, let children, _) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(children == [.leaf(b), .leaf(a), .leaf(c)])
    }

    // MARK: - Move: perpendicular drops wrap the target

    @Test("dropping on a bottom edge stacks the pane under the target")
    func perpendicularDropWrapsTarget() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        // Drag c under b: b's slot becomes a vertical pair, thirds → halves.
        layout.move(c.id, to: b.id, edge: .bottom)

        guard case .split(let axis, let children, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(axis == .horizontal)
        #expect(fractions == [0.5, 0.5])
        #expect(children[0] == .leaf(a))
        #expect(children[1] == .split(axis: .vertical, children: [.leaf(b), .leaf(c)], fractions: [0.5, 0.5]))
    }

    @Test("moving the last sibling out of a container collapses it")
    func movingOutCollapsesContainer() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        layout.move(b.id, to: a.id, edge: .bottom)
        // Root is now a vertical pair [a, b].

        layout.move(b.id, to: a.id, edge: .trailing)

        #expect(layout.root == .split(axis: .horizontal, children: [.leaf(a), .leaf(b)], fractions: [0.5, 0.5]))
    }

    @Test("moving a pane onto itself is a no-op")
    func moveOntoSelfIsNoOp() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let before = layout.root

        layout.move(a.id, to: a.id, edge: .leading)

        #expect(layout.root == before)
        _ = b
    }

    // MARK: - Resize

    @Test("setBoundary adjusts adjacent sibling fractions within a container")
    func setBoundaryAdjustsFractions() {
        let layout = TileLayout()
        _ = layout.openApp("a")
        _ = layout.openApp("b")
        _ = layout.openApp("c")

        // Boundary after the first third moved to 50%.
        layout.setBoundary(path: [], after: 0, to: 0.5)

        guard case .split(_, _, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(abs(fractions[0] - 0.5) < 0.0001)
        #expect(abs(fractions[1] - (1.0 / 3.0 + 1.0 / 3.0 - 0.5)) < 0.0001)
        #expect(abs(fractions[2] - 1.0 / 3.0) < 0.0001)
    }

    @Test("setBoundary clamps so no sibling collapses below its minimum")
    func setBoundaryClamps() {
        let layout = TileLayout()
        _ = layout.openApp("a")
        _ = layout.openApp("b")

        layout.setBoundary(path: [], after: 0, to: 0.99)

        guard case .split(_, _, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(fractions[0] <= 0.9 + 0.0001)
        #expect(fractions[1] >= 0.1 - 0.0001)
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

        layout.move(a.id, to: b.id, edge: .bottom)

        #expect(layout.magnifiedBlockID == nil)
    }
}
