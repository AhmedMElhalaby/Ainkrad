import Foundation

/// The rendered outcome of a tool call: its result text, whether it failed,
/// and whether a result has arrived yet. Pending == the tool is still running.
struct ToolResultSummary: Equatable {
    let text: String
    let isError: Bool
    let isPending: Bool
}

/// Pure search for the `.toolResult` matching a `tool_use` id in the messages
/// that follow the call. Lifted out of `AssistantRootView` so the verdict
/// (`isError`) is preserved and the logic is unit-testable.
enum ToolResultLookup {
    static func summary(forToolUseID id: String, after index: Int, in messages: [AgentMessage]) -> ToolResultSummary {
        guard index + 1 < messages.count else {
            return ToolResultSummary(text: "Running…", isError: false, isPending: true)
        }
        for message in messages[(index + 1)...] {
            for block in message.content {
                if case .toolResult(let toolUseID, let content, let isError) = block, toolUseID == id {
                    return ToolResultSummary(text: content, isError: isError, isPending: false)
                }
            }
        }
        return ToolResultSummary(text: "Running…", isError: false, isPending: true)
    }
}
