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
}
