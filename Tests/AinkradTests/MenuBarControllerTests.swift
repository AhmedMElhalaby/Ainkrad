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

    @Test func teardownRemovesStatusItem() {
        let (c, _) = make()
        c.install()
        c.teardown()
        #expect(c.hasStatusItemForTesting == false)
    }
}
