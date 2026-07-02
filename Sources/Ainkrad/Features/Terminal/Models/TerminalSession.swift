import Foundation
import Observation

/// One Terminal Block's local state — created when its root view appears
/// and torn down when it disappears. Not shared across app launches, not
/// persisted. See Terminal App Architecture.md.
@MainActor
@Observable
final class TerminalSession {
    let id: UUID
    var workingDirectory: URL
    var shellPath: String
    /// Calm, non-blocking messages about configured values that were
    /// rejected during resolution (invalid shell / working directory) —
    /// surfaced inline by the Terminal Block, never as a modal. See
    /// Terminal App Architecture.md.
    let startupNotices: [String]
    private(set) var isRunning = true

    init(id: UUID = UUID(), workingDirectory: URL, shellPath: String, startupNotices: [String] = []) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath
        self.startupNotices = startupNotices
    }

    func terminate() {
        isRunning = false
    }
}
