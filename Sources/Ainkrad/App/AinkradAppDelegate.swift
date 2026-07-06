import AppKit

/// The app is otherwise pure SwiftUI (no other `NSApplicationDelegate`
/// responsibilities) — this exists solely to intercept termination. ⌘Q, the
/// app menu's Quit, and the Dock's Quit all route through
/// `NSApp.terminate(_:)`, which calls `applicationShouldTerminate(_:)` here
/// before the app actually dies.
@MainActor
final class AinkradAppDelegate: NSObject, NSApplicationDelegate {
    /// Wired from `AinkradHostApp.init` right after `AppEnvironment`
    /// bootstraps. `applicationShouldTerminate(_:)` can in principle fire
    /// before that (e.g. a very early Dock quit) — the fallback below just
    /// lets the app quit rather than hanging with no coordinator to reply.
    var quitCoordinator: QuitCoordinator?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitCoordinator?.requestTerminate() ?? .terminateNow
    }
}
