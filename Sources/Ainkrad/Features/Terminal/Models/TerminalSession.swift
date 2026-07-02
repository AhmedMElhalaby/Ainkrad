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
    private(set) var isRunning = true

    init(id: UUID = UUID(), workingDirectory: URL, shellPath: String) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath
    }

    func terminate() {
        isRunning = false
    }
}
