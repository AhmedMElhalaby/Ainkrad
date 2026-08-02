import Foundation
import Observation

/// Shared live-output buffer for streaming tool calls (today: `run_terminal`),
/// keyed by `tool_use` id. The agent loop runs tool calls one at a time
/// (`AgentSession.execute` is awaited per call in the `for call in calls` loop),
/// so a single `active` id is sufficient. `appendActive` keeps the LONGER of the
/// current/incoming snapshot so an out-of-order MainActor hop from the process's
/// background readability handler can never shrink the visible output.
@MainActor
@Observable
final class ToolStreamStore {
    private var buffers: [String: String] = [:]
    private var active: String?

    func begin(_ toolUseID: String) {
        active = toolUseID
        buffers[toolUseID] = ""
    }

    func appendActive(_ snapshot: String) {
        guard let active else { return }
        let current = buffers[active] ?? ""
        if snapshot.utf8.count >= current.utf8.count { buffers[active] = snapshot }
    }

    /// Read accessor for the id currently accepting appends.
    var activeID: String? { active }

    /// Id-checked append: a snapshot only lands if `id` is still the active call.
    /// Guards against a stale background-queue snapshot from a finished call
    /// hopping onto the MainActor after a successor call has already begun.
    func appendActive(_ snapshot: String, for id: String) {
        guard active == id else { return }
        let current = buffers[id] ?? ""
        if snapshot.utf8.count >= current.utf8.count { buffers[id] = snapshot }
    }

    func finish(_ toolUseID: String, finalOutput: String) {
        buffers[toolUseID] = finalOutput
        if active == toolUseID { active = nil }
    }

    func liveOutput(for toolUseID: String) -> String? { buffers[toolUseID] }
}
