import Testing
import CoreGraphics
@testable import Ainkrad

/// The Workspace Overview panel hugs its content, which only works while every
/// region inside it can state a definite height. These are those statements —
/// a `ScrollView` left to itself claims every point offered, so if one of these
/// heights drifts away from the rows it is describing, the panel silently goes
/// back to being a fixed slab (too tall) or starts clipping (too short).
@Suite("Workspace Overview panel height")
struct WorkspaceOverviewLayoutTests {

    // MARK: - App grid

    @Test("an empty app grid asks for nothing beyond its padding")
    func emptyGridIsMinimal() {
        #expect(WorkspaceOverviewView.appGridHeight(count: 0) == 16)
    }

    @Test("the grid is three across, so one to three panes occupy exactly one row")
    func oneRowUpToThree() {
        let oneRow = WorkspaceOverviewView.appGridHeight(count: 1)
        #expect(WorkspaceOverviewView.appGridHeight(count: 2) == oneRow)
        #expect(WorkspaceOverviewView.appGridHeight(count: 3) == oneRow)
        #expect(WorkspaceOverviewView.appGridHeight(count: 4) > oneRow)
    }

    @Test("height grows one row at a time, never per pane")
    func growsByRows() {
        let rowOne = WorkspaceOverviewView.appGridHeight(count: 3)
        let rowTwo = WorkspaceOverviewView.appGridHeight(count: 6)
        let rowThree = WorkspaceOverviewView.appGridHeight(count: 9)
        #expect(rowTwo - rowOne == rowThree - rowTwo)
    }

    @Test("a workspace with many panes is capped, so the grid scrolls instead of pushing the preview off the panel")
    func manyPanesAreCapped() {
        let capped = WorkspaceOverviewView.appGridHeight(count: 200)
        #expect(capped == 262)
        #expect(WorkspaceOverviewView.appGridHeight(count: 40) <= 262)
    }

    @Test("height never decreases as panes are added")
    func monotonic() {
        var previous: CGFloat = 0
        for count in 0...30 {
            let height = WorkspaceOverviewView.appGridHeight(count: count)
            #expect(height >= previous)
            previous = height
        }
    }

    /// The panel's ceiling has to clear the tallest content the panel can hold on
    /// a large window, or a busy workspace overflows the chrome rather than
    /// scrolling inside it.
    @Test("the tallest possible detail column still fits under the panel's maximum")
    func tallestContentFitsUnderCeiling() {
        let detail = WorkspaceOverviewView.detailHeaderHeight
            + WorkspaceOverviewView.maximumPreviewHeight
            + WorkspaceOverviewView.appSectionHeaderHeight
            + WorkspaceOverviewView.appGridHeight(count: 200)
        let panel = WorkspaceOverviewView.panelChromeHeight + detail
        #expect(panel <= WorkspaceOverviewView.maximumPanelHeight)
    }

    // MARK: - Ceiling

    @Test("the ceiling tracks the window but never exceeds the panel's maximum")
    func ceilingTracksWindow() {
        #expect(WorkspaceOverviewView.ceiling(forWindowHeight: 2000)
                == WorkspaceOverviewView.maximumPanelHeight)
        let mid = WorkspaceOverviewView.ceiling(forWindowHeight: 800)
        #expect(mid > 420)
        #expect(mid < WorkspaceOverviewView.maximumPanelHeight)
    }

    /// The first attempt at hugging used `fixedSize`, which refuses to shrink —
    /// so on a window shorter than the content the panel overflowed instead of
    /// adapting. The ceiling has to win in that direction.
    @Test("a short window clamps the panel rather than letting it overflow")
    func shortWindowClampsRatherThanOverflows() {
        let tiny = WorkspaceOverviewView.ceiling(forWindowHeight: 300)
        #expect(tiny == 420)

        let tallestContent = WorkspaceOverviewView.panelChromeHeight
            + WorkspaceOverviewView.detailHeaderHeight
            + WorkspaceOverviewView.maximumPreviewHeight
            + WorkspaceOverviewView.appSectionHeaderHeight
            + WorkspaceOverviewView.appGridHeight(count: 200)
        #expect(min(tallestContent, tiny) == tiny)
    }

    /// An empty workspace has nothing to preview, and used to be given a
    /// full-size preview saying "empty" AND a separate "No apps" block — making
    /// the emptiest workspace the tallest thing the panel had to show, which is
    /// what stopped it hugging at all.
    @Test("an empty workspace asks for far less height than a busy one")
    func emptyWorkspaceIsShorterThanABusyOne() {
        let empty = WorkspaceOverviewView.detailHeaderHeight
            + WorkspaceOverviewView.emptyWorkspaceHeight + 16
        let busy = WorkspaceOverviewView.detailHeaderHeight
            + WorkspaceOverviewView.maximumPreviewHeight + 14
            + WorkspaceOverviewView.appSectionHeaderHeight
            + WorkspaceOverviewView.appGridHeight(count: 3)

        #expect(empty < busy)
        // And comfortably inside even the smallest ceiling, so the shortest
        // possible content can always actually hug.
        #expect(WorkspaceOverviewView.panelChromeHeight + empty < 420)
    }

    @Test("the preview can shrink but not below the point where its cells stop reading")
    func previewHasARange() {
        #expect(WorkspaceOverviewView.minimumPreviewHeight
                < WorkspaceOverviewView.maximumPreviewHeight)
        #expect(WorkspaceOverviewView.minimumPreviewHeight > 0)
    }
}
