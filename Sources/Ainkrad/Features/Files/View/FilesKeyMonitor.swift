import AppKit
import SwiftUI

/// Local `keyDown` monitor for Files' chorded shortcuts.
///
/// Follows `ComposerTabCycleMonitor`'s established pattern rather than
/// SwiftUI's `.onKeyPress`. Two rounds of trying to make ⌘⇧F work through
/// `onKeyPress` failed: the modifier chord either never matched, or the
/// container's focus was elsewhere so the handler never ran at all. A local
/// monitor sees the event regardless of which subview holds focus, which is
/// exactly why the Assistant reaches for one too.
///
/// Matching is by `keyCode`, not by character: with Shift held the character
/// becomes "F", and matching on the character is what made the SwiftUI
/// version's key set unreliable in the first place.
struct FilesKeyMonitor: NSViewRepresentable {
    /// ⌘⇧F — focus the in-pane scoped search field.
    let onFocusScopedSearch: () -> Void

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.onFocusScopedSearch = onFocusScopedSearch
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.onFocusScopedSearch = onFocusScopedSearch
    }

    static func dismantleNSView(_ nsView: MonitoringView, coordinator: ()) {
        nsView.teardown()
    }

    final class MonitoringView: NSView {
        /// `kVK_ANSI_F`. Layout-independent, unlike the produced character.
        private static let fKeyCode: UInt16 = 3

        var onFocusScopedSearch: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    // Exactly command+shift — command alone is the GLOBAL
                    // search palette and must keep passing through.
                    guard event.keyCode == Self.fKeyCode,
                          flags == [.command, .shift] else { return event }
                    self.onFocusScopedSearch?()
                    return nil   // swallow, so it doesn't also beep
                }
            } else {
                teardown()
            }
        }

        func teardown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        // No `deinit` cleanup: the monitor is `Any?`, which is not `Sendable`,
        // and Swift 6 forbids touching it from a nonisolated `deinit`.
        // `viewDidMoveToWindow(nil)` and `dismantleNSView` both call
        // `teardown()`, which covers every real removal path.
    }
}
