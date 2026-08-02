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

    /// True while the status item must not exist — today, while the first-run
    /// setup gate is up. Wired in `AinkradHostApp.install(_:into:)`.
    ///
    /// The gate is a full-screen scrim inside the WINDOW plus a window-local
    /// `keyDown` monitor. The status item is neither: it lives on
    /// `NSStatusBar.system` and its popover is an `NSPopover` anchored to the
    /// status button, so it is reachable with the mouse while every in-window
    /// surface is blocked. Through it the whole Sage is reachable, and
    /// every action there (a composed message, an agent switch, a pinned model,
    /// "Open in the Sage pane") persists into the PROVISIONAL home that the
    /// Home step's swap then silently discards — the same class of bug the
    /// `.commands` block was gated for. `onManageConnections` is worse still: it
    /// latches `isSettingsPresented` invisibly beneath the gate.
    ///
    /// Suppression is enforced at BOTH ends — no status item is created while
    /// the gate is up, and a click on one that somehow exists does nothing —
    /// because the gate can be raised after an install only in principle, and a
    /// silent reachable Sage is not a failure worth being subtle about.
    var isSuppressed: () -> Bool = { false }

    func install() {
        guard statusItem == nil, !isSuppressed() else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles",
                                   accessibilityDescription: "Ainkrad Sage")
            button.image?.isTemplate = true
            button.action = #selector(statusButtonClicked)
            button.target = self
        }
        statusItem = item

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: content())
    }

    @objc private func statusButtonClicked() {
        guard !isSuppressed() else { return }
        togglePopover()
    }

    /// Test-only entry to the button's real action, so the suppression guard is
    /// covered rather than only the code path around it.
    func statusButtonClickedForTesting() { statusButtonClicked() }

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
