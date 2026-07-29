import Testing
import SwiftUI
import AinkradAppKit
import AinkradAppKitContract

@Suite("SettingsPageView")
@MainActor
struct SettingsPageViewTests {
    private func page(groupCount: Int) -> SettingsPage {
        let root = SettingsPath(["test", "page"])
        return SettingsPage(
            path: root, title: "Test", icon: "gear", group: .workspace, order: 0,
            groups: (0..<groupCount).map { i in
                SettingsGroup(path: root.appending("g\(i)"), title: "Group \(i)", fields: [
                    SettingsField(path: root.appending("g\(i)").appending("f"),
                                  label: "Field", kind: .toggle(.constant(false)))
                ])
            })
    }

    @Test("the mini-map needs both four groups and enough width")
    func miniMapVisibility() {
        #expect(!SettingsPageView.showsMiniMap(page: page(groupCount: 3), width: 1000))
        #expect(!SettingsPageView.showsMiniMap(page: page(groupCount: 4), width: 600))
        #expect(SettingsPageView.showsMiniMap(page: page(groupCount: 4), width: 1000))
    }

    @Test("filtering dims rather than removes — every field still renders")
    func filterIsNonDestructive() {
        let p = page(groupCount: 2)
        let matched: Set<SettingsPath> = [p.groups[0].fields[0].path]
        #expect(SettingsGroupView.opacity(for: p.groups[1].fields[0].path, matchedPaths: matched) == 0.35)
        #expect(SettingsGroupView.opacity(for: p.groups[0].fields[0].path, matchedPaths: matched) == 1.0)
        #expect(SettingsGroupView.opacity(for: p.groups[1].fields[0].path, matchedPaths: nil) == 1.0)
    }

    @Test("a group's hit count counts only its own matches")
    func hitCounts() {
        let p = page(groupCount: 2)
        let matched: Set<SettingsPath> = [p.groups[0].fields[0].path]
        #expect(SettingsGroupView.hitCount(group: p.groups[0], matchedPaths: matched) == 1)
        #expect(SettingsGroupView.hitCount(group: p.groups[1], matchedPaths: matched) == 0)
    }

    @Test("row width accounts for the mini-map's occupied space, not just total width")
    func rowAreaWidthSubtractsMiniMap() {
        let p = page(groupCount: 4)
        // Total width is comfortably past the wide breakpoint (900), but once
        // the mini-map's ~168pt is subtracted the rows don't actually have
        // side-by-side room. If the mini-map's width were ignored, this would
        // report a width still >= wideBreakpoint and pick .sideBySide.
        let total: CGFloat = 950
        let rowWidth = SettingsPageView.rowAreaWidth(page: p, totalWidth: total)
        #expect(rowWidth == total - SettingsPageView.miniMapOccupiedWidth)
        #expect(SettingsRowLayout(detailWidth: rowWidth) == .stacked)

        // No mini-map (too few groups) — the full width is available to rows.
        let noMiniMap = page(groupCount: 3)
        #expect(SettingsPageView.rowAreaWidth(page: noMiniMap, totalWidth: total) == total)
    }
}
