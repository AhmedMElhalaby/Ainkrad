import Testing
import Foundation
@testable import Ainkrad

@Suite("Revealing a notification's source")
struct SignalRevealTests {
    private let activeID = UUID()
    private let otherID = UUID()

    private func workspace(_ id: UUID, _ panes: [(String, UUID)]) -> SignalRevealWorkspace {
        SignalRevealWorkspace(id: id, panes: panes.map {
            SignalRevealWorkspace.Pane(appID: $0.0, blockID: $0.1)
        })
    }

    @Test("an open pane in the active workspace is focused, not duplicated")
    func focusesExistingPane() {
        let block = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("rune", block)])],
            activeWorkspaceID: activeID)
        #expect(action == .focus(workspaceID: activeID, blockID: block),
                "opening a second empty terminal takes the user further from the session")
    }

    @Test("a pane on another workspace is focused there")
    func focusesAcrossWorkspaces() {
        let block = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("lore", UUID())]),
                         workspace(otherID, [("rune", block)])],
            activeWorkspaceID: activeID)
        #expect(action == .focus(workspaceID: otherID, blockID: block))
    }

    @Test("the active workspace wins when the app is open in both")
    func prefersTheActiveWorkspace() {
        let here = UUID()
        let there = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("rune", here)]),
                         workspace(otherID, [("rune", there)])],
            activeWorkspaceID: activeID)
        #expect(action == .focus(workspaceID: activeID, blockID: here),
                "yanking the user to another workspace is a bigger disruption than the ping")
    }

    @Test("an app that is not open anywhere opens")
    func opensWhenAbsent() {
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("lore", UUID())])],
            activeWorkspaceID: activeID)
        #expect(action == .openNewPane)
    }

    @Test("an overlay app is presented, never tiled")
    func overlayAppsArePresented() {
        let action = SignalReveal.action(
            appID: "hoard", presentsAsOverlay: true,
            workspaces: [workspace(activeID, [])],
            activeWorkspaceID: activeID)
        #expect(action == .presentOverlay)
    }

    @Test("the first matching pane wins when one app has several")
    func firstPaneWins() {
        let first = UUID()
        let action = SignalReveal.action(
            appID: "rune", presentsAsOverlay: false,
            workspaces: [workspace(activeID, [("rune", first), ("rune", UUID())])],
            activeWorkspaceID: activeID)
        #expect(action == .focus(workspaceID: activeID, blockID: first))
    }
}
