import Foundation
import SwiftUI
import Testing
@testable import Ainkrad

@Suite("MenuBarController")
@MainActor
struct MenuBarControllerTests {
    private func make() -> (MenuBarController, MenuBarPresence) {
        let presence = MenuBarPresence(runs: EmptyMenuBarRunSource())
        let c = MenuBarController(presence: presence) { AnyView(EmptyView()) }
        return (c, presence)
    }

    @Test func installCreatesStatusItem() {
        let (c, _) = make(); defer { c.teardown() }
        c.install()
        #expect(c.hasStatusItemForTesting == true)
    }

    @Test func togglePopoverSyncsPresence() {
        let (c, presence) = make(); defer { c.teardown() }
        c.install()
        c.togglePopover()
        #expect(presence.isPopoverOpen == true)
        c.togglePopover()
        #expect(presence.isPopoverOpen == false)
    }

    /// The first-run gate is a full-screen scrim INSIDE the window plus a
    /// window-local key monitor. The status item is on `NSStatusBar.system` and
    /// its popover is anchored outside the window, so neither reaches it — it
    /// was the one route to the full Sage while setup was still running,
    /// and everything done through it persisted into the provisional home that
    /// the Home step's swap discards. It must simply not exist while gated.
    @Test func suppressedInstallCreatesNoStatusItem() {
        let (c, _) = make(); defer { c.teardown() }
        var gated = true
        c.isSuppressed = { gated }
        c.install()
        #expect(c.hasStatusItemForTesting == false)

        // ...and it comes back the moment the gate drops, since the two
        // gate-lowering sites re-call `install()`.
        gated = false
        c.install()
        #expect(c.hasStatusItemForTesting == true)
    }

    /// Belt and braces: a status item that exists while the gate is up (it
    /// cannot today, but the gate could in principle be raised after an
    /// install) must not open the popover either.
    @Test func suppressedClickDoesNotOpenThePopover() {
        let (c, presence) = make(); defer { c.teardown() }
        c.install()
        #expect(c.hasStatusItemForTesting == true)
        c.isSuppressed = { true }
        c.statusButtonClickedForTesting()
        #expect(presence.isPopoverOpen == false)
    }

    @Test func teardownRemovesStatusItem() {
        let (c, _) = make()
        c.install()
        c.teardown()
        #expect(c.hasStatusItemForTesting == false)
    }
}
