import Testing
import SwiftUI
@testable import Ainkrad

@MainActor
@Suite("SignalBellController")
final class SignalBellControllerTests {
    private func makeController() -> SignalBellController {
        SignalBellController(content: { AnyView(EmptyView()) })
    }

    @Test("install creates a status item")
    func installsStatusItem() {
        let controller = makeController()
        controller.install()
        #expect(controller.hasStatusItemForTesting)
        controller.teardown()
        #expect(!controller.hasStatusItemForTesting)
    }

    @Test("no bell exists while the setup gate is up")
    func suppressedDuringSetupGate() {
        let controller = makeController()
        controller.isSuppressed = { true }
        controller.install()
        #expect(!controller.hasStatusItemForTesting,
                "the gate blocks in-window surfaces only; a status item would route around it")
    }

    @Test("a suppressed bell that somehow exists does nothing when clicked")
    func suppressedClickIsInert() {
        let controller = makeController()
        controller.install()
        controller.isSuppressed = { true }
        controller.statusButtonClickedForTesting()
        #expect(!controller.isPopoverShownForTesting)
        controller.teardown()
    }

    @Test("the badge shows the unread count and disappears at zero")
    func badge() {
        let controller = makeController()
        controller.install()
        controller.updateBadge(unread: 7)
        #expect(controller.badgeTextForTesting == "7")
        controller.updateBadge(unread: 0)
        #expect(controller.badgeTextForTesting == nil)
        controller.updateBadge(unread: 150)
        #expect(controller.badgeTextForTesting == "99+", "a four-digit badge would resize the menu bar")
        controller.teardown()
    }
}
