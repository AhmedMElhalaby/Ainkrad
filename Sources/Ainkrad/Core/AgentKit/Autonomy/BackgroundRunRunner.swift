// Sources/Ainkrad/Core/AgentKit/Autonomy/BackgroundRunRunner.swift
import Foundation

/// The production `AgentRunRunner`: drives a fresh, headless `AgentSession`
/// per run to completion. A new session per call (rather than one shared
/// session) keeps concurrent runs' transcripts from clobbering each other —
/// `RunManager` can have up to `maxConcurrent` of these executing at once.
///
/// Mirrors `AgentSessionSubagentRunner.run`'s "drive a child session to
/// settlement" shape: `send`, await `currentTask`, map the final state.
/// Failure isolation matches too — a child that settles into `.failed` maps
/// to `.failure`, never throws.
///
/// Background runs are built `unattended: true` by the injected `makeSession`
/// closure (Task 8's gate: a requireApproval tool auto-denies rather than
/// parking on a HUD nothing will ever answer). Trust tier `.background`
/// (Slice 6, wired in Task 21) is not yet threaded through — until then a
/// background run executes on the host session's own connections/tools like
/// a normal (but unattended) turn.
@MainActor
final class BackgroundRunRunner: AgentRunRunner {
    private let makeSession: @MainActor () -> AgentSession

    init(makeSession: @escaping @MainActor () -> AgentSession) {
        self.makeSession = makeSession
    }

    func execute(prompt: String, appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
        let session = makeSession()
        session.send(prompt)
        await session.currentTask?.value

        if case .failed(let message) = session.state {
            appendLog(message)
            return .failure(message)
        }
        let text = session.messages.last { $0.role == .assistant }?.text ?? ""
        if !text.isEmpty { appendLog(text) }
        return .success(text)
    }
}
