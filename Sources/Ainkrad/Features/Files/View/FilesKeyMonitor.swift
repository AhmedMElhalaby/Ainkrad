import AppKit
import SwiftUI

/// Local `keyDown` monitor for Files' chorded shortcuts.
///
/// Follows `ComposerTabCycleMonitor`'s established pattern rather than
/// SwiftUI's `.onKeyPress`, which only fires while its container holds focus —
/// unreliable in a pane where the caret may be in the list, the breadcrumb or
/// a field. A local monitor sees the event whoever has focus.
///
/// **⌥F, not ⌘⇧F.** The original chord never reached the app even through this
/// monitor, which means it is claimed above us — a local monitor runs before
/// the app's own responder chain but AFTER system-level bindings, so anything
/// macOS or another app has taken is simply invisible here. ⌥F is unclaimed.
///
/// Matching is by `keyCode`, never by character: ⌥F produces "ƒ", so character
/// matching would silently fail exactly the way the SwiftUI version did.
struct FilesKeyMonitor: NSViewRepresentable {
    /// ⌥F — focus the in-pane scoped search field.
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
                    // Exactly option — ⌘F (global palette) and ⌘⇧F must both
                    // keep passing through untouched.
                    guard event.keyCode == Self.fKeyCode,
                          flags == .option else { return event }
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
