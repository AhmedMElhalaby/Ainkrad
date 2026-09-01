import AppKit
import SwiftUI

/// Owns the Signal bell's `NSStatusItem` and its feed popover.
///
/// A SECOND status item rather than a tab inside the Sage popover: that
/// popover is `.transient` and holds a conversation, so a feed living inside
/// it would compete for the same space and dismiss on every interaction.
///
/// The suppression doctrine is carried over from `MenuBarController` verbatim,
/// and for the same reason. The first-run setup gate is a full-screen scrim
/// inside the WINDOW; a status item lives on `NSStatusBar.system` and is
/// reachable with the mouse while every in-window surface is blocked. Through
/// the feed's deep-links the user could open apps behind the scrim. So it is
/// enforced at BOTH ends: no status item is created while the gate is up, and
/// a click on one that somehow exists does nothing.
@MainActor
final class SignalBellController: NSObject, NSPopoverDelegate {
    private let content: () -> AnyView
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var isPopoverOpen = false

    init(content: @escaping () -> AnyView) {
        self.content = content
        super.init()
    }

    var isSuppressed: () -> Bool = { false }

    var hasStatusItemForTesting: Bool { statusItem != nil }
    var isPopoverShownForTesting: Bool { isPopoverOpen }
    /// The badge value itself, not the button's title: the title carries a
    /// leading space for spacing against the glyph, which is presentation.
    private(set) var badgeText: String?
    var badgeTextForTesting: String? { badgeText }

    func install() {
        guard statusItem == nil, !isSuppressed() else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bell",
                                   accessibilityDescription: "Ainkrad notifications")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            button.action = #selector(statusButtonClicked)
            button.target = self
        }
        statusItem = item

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: content())
    }

    /// Renders the unread count beside the glyph. Capped at "99+": the status
    /// item is variable-length, so a four-digit count silently widens the menu
    /// bar and shoves the user's other items along.
    func updateBadge(unread: Int) {
        badgeText = Self.badgeText(unread)
        statusItem?.button?.title = badgeText.map { " \($0)" } ?? ""
    }

    static func badgeText(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case ...99: return String(count)
        default: return "99+"
        }
    }

    @objc private func statusButtonClicked() {
        guard !isSuppressed() else { return }
        togglePopover()
    }

    /// Test-only entry to the button's real action, so the suppression guard is
    /// covered rather than only the code path around it.
    func statusButtonClickedForTesting() { statusButtonClicked() }

    func togglePopover() { isPopoverOpen ? hidePopover() : showPopover() }

    func showPopover() {
        guard let button = statusItem?.button, !isPopoverOpen else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        isPopoverOpen = true
    }

    func hidePopover() {
        popover.performClose(nil)
        isPopoverOpen = false
    }

    // Keep the flag truthful when the transient popover self-dismisses
    // (click-outside), which does not route through `hidePopover()`.
    func popoverDidClose(_ notification: Notification) { isPopoverOpen = false }

    func teardown() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }
}
