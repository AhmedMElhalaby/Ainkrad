import Foundation

/// The result of executing an `AgentRun`'s prompt to completion.
enum AgentRunOutcome: Sendable {
    case success(String)
    case failure(String)
}

/// Executes a run's prompt to completion, streaming log lines back. The
/// production impl drives a headless `AgentSession` (Task 6 / Task 11 wiring);
/// tests inject a stub.
@MainActor
protocol AgentRunRunner: AnyObject {
    func execute(prompt: String, appendLog: @escaping (String) -> Void) async -> AgentRunOutcome
}
