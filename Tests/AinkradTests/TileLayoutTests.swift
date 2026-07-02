import Testing
@testable import Ainkrad

@Suite("TileLayout")
struct TileLayoutTests {

    @Test("a new layout starts empty with no focused Block")
    func startsEmpty() {
        let layout = TileLayout()
        #expect(layout.isEmpty)
        #expect(layout.focusedBlockID == nil)
    }

    @Test("opening an app on an empty layout fills the whole canvas and focuses it")
    func openOnEmptyFillsCanvas() {
        let layout = TileLayout()
        let block = layout.openApp("terminal")

        #expect(!layout.isEmpty)
        #expect(layout.root == .leaf(block))
        #expect(layout.focusedBlockID == block.id)
    }

    @Test("opening a second app splits the focused Block vertically, new Block second, and focuses it")
    func openSecondAppSplitsFocusedBlock() {
        let layout = TileLayout()
        let terminal = layout.openApp("terminal")
        let settings = layout.openApp("settings")

        #expect(layout.root == .split(axis: .vertical, ratio: 0.5, first: .leaf(terminal), second: .leaf(settings)))
        #expect(layout.focusedBlockID == settings.id)
    }

    @Test("multiple Blocks of the same app are allowed as distinct leaves")
    func multipleBlocksOfSameAppAllowed() {
        let layout = TileLayout()
        let first = layout.openApp("terminal")
        let second = layout.openApp("terminal")

        #expect(first.id != second.id)
        #expect(layout.root == .split(axis: .vertical, ratio: 0.5, first: .leaf(first), second: .leaf(second)))
    }

    @Test("closing the last Block returns the layout to the empty state")
    func closingLastBlockReturnsToEmpty() {
        let layout = TileLayout()
        let block = layout.openApp("terminal")

        layout.close(block.id)

        #expect(layout.isEmpty)
        #expect(layout.focusedBlockID == nil)
    }

    @Test("closing one of two split Blocks promotes its sibling to fill the freed space")
    func closingOneOfTwoPromotesSibling() {
        let layout = TileLayout()
        let terminal = layout.openApp("terminal")
        let settings = layout.openApp("settings")

        layout.close(terminal.id)

        #expect(layout.root == .leaf(settings))
        #expect(layout.focusedBlockID == settings.id)
    }

    @Test("closing a non-focused Block does not change focus")
    func closingNonFocusedBlockKeepsFocus() {
        let layout = TileLayout()
        let terminal = layout.openApp("terminal")
        let settings = layout.openApp("settings")
        layout.focus(terminal.id)

        layout.close(settings.id)

        #expect(layout.root == .leaf(terminal))
        #expect(layout.focusedBlockID == terminal.id)
    }

    @Test("focus(_:) changes the focused Block without altering the tree")
    func focusChangesFocusedBlock() {
        let layout = TileLayout()
        let terminal = layout.openApp("terminal")
        let settings = layout.openApp("settings")

        layout.focus(terminal.id)

        #expect(layout.focusedBlockID == terminal.id)
        #expect(layout.root == .split(axis: .vertical, ratio: 0.5, first: .leaf(terminal), second: .leaf(settings)))
    }

    @Test("setRatio adjusts the ratio of the split containing the given Block")
    func setRatioAdjustsSplit() {
        let layout = TileLayout()
        let terminal = layout.openApp("terminal")
        let settings = layout.openApp("settings")

        layout.setRatio(0.3, for: terminal.id)

        #expect(layout.root == .split(axis: .vertical, ratio: 0.3, first: .leaf(terminal), second: .leaf(settings)))
    }

    @Test("appIDs lists every open Block's app in leaf order")
    func appIDsListsOpenApps() {
        let layout = TileLayout()
        #expect(layout.appIDs.isEmpty)

        layout.openApp("terminal")
        layout.openApp("settings")
        layout.openApp("terminal")

        #expect(layout.appIDs == ["terminal", "settings", "terminal"])
    }

    // MARK: - Drag-to-rearrange (move)

    @Test("moving a Block onto another's trailing edge splits vertically, moved Block second")
    func moveToTrailingEdge() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")
        // Tree: split(split(a, b-was-replaced...)) — actual: a | (b | c) after two opens?
        // openApp splits the focused leaf: after 3 opens the tree is
        // split(a, split(b, c)) — c focused.

        layout.move(a.id, to: c.id, edge: .trailing)

        // a removed (its sibling promotes), then re-split onto c's right.
        #expect(layout.root == .split(
            axis: .vertical, ratio: 0.5,
            first: .leaf(b),
            second: .split(axis: .vertical, ratio: 0.5, first: .leaf(c), second: .leaf(a))
        ))
        #expect(layout.focusedBlockID == a.id)
    }

    @Test("moving a Block onto another's top edge splits horizontally, moved Block first")
    func moveToTopEdge() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")

        layout.move(b.id, to: a.id, edge: .top)

        #expect(layout.root == .split(axis: .horizontal, ratio: 0.5, first: .leaf(b), second: .leaf(a)))
    }

    @Test("moving a Block onto itself is a no-op")
    func moveOntoSelfIsNoOp() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let before = layout.root

        layout.move(b.id, to: b.id, edge: .leading)

        #expect(layout.root == before)
        _ = a
    }

    @Test("moving the only Block is a no-op")
    func moveOnlyBlockIsNoOp() {
        let layout = TileLayout()
        let a = layout.openApp("a")

        layout.move(a.id, to: a.id, edge: .top)

        #expect(layout.root == .leaf(a))
    }

    // MARK: - Magnify

    @Test("toggleMagnify magnifies a Block and toggles back off")
    func toggleMagnifyTogglesOnAndOff() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        layout.openApp("b")

        layout.toggleMagnify(a.id)
        #expect(layout.magnifiedBlockID == a.id)

        layout.toggleMagnify(a.id)
        #expect(layout.magnifiedBlockID == nil)
    }

    @Test("magnifying a different Block replaces the current magnification")
    func magnifyDifferentBlockReplaces() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")

        layout.toggleMagnify(a.id)
        layout.toggleMagnify(b.id)

        #expect(layout.magnifiedBlockID == b.id)
    }

    @Test("closing the magnified Block clears magnification")
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

    @Test("moving a Block clears magnification")
    func movingBlockClearsMagnification() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        layout.toggleMagnify(a.id)

        layout.move(a.id, to: b.id, edge: .bottom)

        #expect(layout.magnifiedBlockID == nil)
    }
}
