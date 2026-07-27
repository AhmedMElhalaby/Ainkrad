import AppKit
import SwiftUI

/// Owns the app-lifetime `NSStatusItem` and its Cardinal-HUD popover. The
/// status item lives on `NSStatusBar.system`, so it is reachable regardless of
/// whether the main window is focused, minimized, or hidden.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let presence: MenuBarPresence
    private let content: () -> AnyView
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    init(presence: MenuBarPresence, content: @escaping () -> AnyView) {
        self.presence = presence
        self.content = content
        super.init()
    }

    /// Test-only visibility into whether the status item is currently installed.
    var hasStatusItemForTesting: Bool { statusItem != nil }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles",
                                   accessibilityDescription: "Ainkrad Assistant")
            button.image?.isTemplate = true
            button.action = #selector(statusButtonClicked)
            button.target = self
        }
        statusItem = item

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: content())
    }

    @objc private func statusButtonClicked() { togglePopover() }

    // Driven by `presence.isPopoverOpen` rather than `popover.isShown`: this
    // class is the sole mutator of both, so they stay in lockstep, and it
    // avoids relying on `NSPopover.isShown` reflecting synchronously across
    // AppKit hosts (e.g. under test).
    func togglePopover() { presence.isPopoverOpen ? hidePopover() : showPopover() }

    func showPopover() {
        guard let button = statusItem?.button, !presence.isPopoverOpen else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        presence.open()
    }

    func hidePopover() {
        popover.performClose(nil)
        presence.close()
    }

    // Keep `presence` truthful when the transient popover self-dismisses
    // (click-outside), which does not route through `hidePopover()`.
    func popoverDidClose(_ notification: Notification) { presence.close() }

    func teardown() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }
}
