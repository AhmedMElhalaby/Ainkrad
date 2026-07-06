/// Seam over `NSApplication.reply(toApplicationShouldTerminate:)`, so
/// `QuitCoordinator` is testable without a real `NSApplication`. Real impl:
/// `AppKitTerminationReplier` (App layer).
@MainActor protocol TerminationReplying {
    func reply(_ shouldTerminate: Bool)
}
