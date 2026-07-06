import AppKit

/// Real `TerminationReplying`: delivers the deferred reply to the real
/// `NSApplication` after `applicationShouldTerminate(_:)` returned
/// `.terminateLater`.
@MainActor
final class AppKitTerminationReplier: TerminationReplying {
    func reply(_ shouldTerminate: Bool) {
        NSApplication.shared.reply(toApplicationShouldTerminate: shouldTerminate)
    }
}
