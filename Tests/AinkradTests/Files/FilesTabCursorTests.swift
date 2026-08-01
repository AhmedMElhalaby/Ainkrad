import Testing
import Foundation
@testable import Ainkrad

@MainActor
@Suite("FilesTab cursor and selection")
struct FilesTabCursorTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func makeTab() -> FilesTab {
        let fs = InMemoryFileSystem(home: home)
        fs.add(directory: "/Users/test", children: ["Documents/", "a.txt", "b.txt"])
        fs.add(directory: "/Users/test/Documents", children: ["report.pdf"])
        return FilesTab(directory: home, fileSystem: fs)
    }

    @Test("cursor starts at the first row")
    func startsAtZero() {
        #expect(makeTab().cursorIndex == 0)
    }

    @Test("moving the cursor clamps at both ends")
    func clamps() {
        let tab = makeTab()
        tab.moveCursor(by: -1)
        #expect(tab.cursorIndex == 0)
        tab.moveCursor(by: 99)
        #expect(tab.cursorIndex == 2)
    }

    @Test("cursorEntry tracks the visible ordering")
    func cursorEntry() {
        let tab = makeTab()
        #expect(tab.cursorEntry?.name == "Documents")
        tab.moveCursor(by: 1)
        #expect(tab.cursorEntry?.name == "a.txt")
    }

    @Test("start and end jump to the extremes")
    func startEnd() {
        let tab = makeTab()
        tab.moveCursorToEnd()
        #expect(tab.cursorIndex == 2)
        tab.moveCursorToStart()
        #expect(tab.cursorIndex == 0)
    }

    @Test("selecting the cursor replaces the selection by default")
    func selectReplaces() {
        let tab = makeTab()
        tab.selectCursor(extending: false)
        tab.moveCursor(by: 1)
        tab.selectCursor(extending: false)
        #expect(tab.selection.count == 1)
    }

    @Test("extending adds to the selection")
    func selectExtends() {
        let tab = makeTab()
        tab.selectCursor(extending: false)
        tab.moveCursor(by: 1)
        tab.selectCursor(extending: true)
        #expect(tab.selection.count == 2)
    }

    @Test("select all and invert")
    func selectAllAndInvert() {
        let tab = makeTab()
        tab.selectAll()
        #expect(tab.selection.count == 3)
        tab.invertSelection()
        #expect(tab.selection.isEmpty)
    }

    @Test("invert on a partial selection selects the complement")
    func invertPartial() {
        let tab = makeTab()
        tab.selectCursor(extending: false)
        tab.invertSelection()
        #expect(tab.selection.count == 2)
        #expect(!tab.selection.contains(tab.visibleEntries[0].url))
    }

    @Test("activating a directory descends and resets the cursor")
    func activateDescends() {
        let tab = makeTab()
        tab.activateCursor()
        #expect(tab.currentDirectory == home.appendingPathComponent("Documents"))
        #expect(tab.cursorIndex == 0)
    }

    @Test("the cursor stays in range when the listing shrinks")
    func cursorSurvivesShrink() {
        let tab = makeTab()
        tab.moveCursorToEnd()
        tab.showHidden = true
        tab.navigate(to: home.appendingPathComponent("Documents"))
        #expect(tab.cursorIndex == 0)
        #expect(tab.cursorEntry?.name == "report.pdf")
    }
}
