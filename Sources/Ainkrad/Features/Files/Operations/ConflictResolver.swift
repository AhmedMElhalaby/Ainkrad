import Foundation
import Observation

/// Bridges the engine's `async` conflict question to a SwiftUI sheet, and
/// remembers an apply-to-all answer so a 200-file conflict is one decision
/// rather than two hundred.
@MainActor
@Observable
final class ConflictResolver {
    /// Non-nil while a sheet should be showing.
    private(set) var pending: ConflictQuestion?
    /// Set once the user answers with "apply to all"; every later conflict in
    /// the same run is answered from here without asking.
    private(set) var blanketAnswer: ConflictAnswer?

    private var continuation: CheckedContinuation<ConflictAnswer, Never>?

    /// Handed to `FileOperationEngine.submit(_:conflictResolver:)`.
    func resolve(_ question: ConflictQuestion) async -> ConflictAnswer {
        if let blanketAnswer { return blanketAnswer }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pending = question
        }
    }

    func answer(_ answer: ConflictAnswer) {
        if answer.applyToAll { blanketAnswer = answer }
        pending = nil
        continuation?.resume(returning: answer)
        continuation = nil
    }

    /// Dismissing the sheet without choosing means skip — the only safe
    /// default, since the alternative destroys something.
    func cancel() {
        answer(.skipOnce)
    }

    /// Called between operations so one batch's "apply to all" never leaks
    /// into the next.
    func reset() {
        blanketAnswer = nil
    }
}
