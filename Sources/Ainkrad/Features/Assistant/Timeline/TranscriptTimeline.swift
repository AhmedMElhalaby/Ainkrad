import Foundation
import AinkradHostRuntime

/// Status of a single timeline step. `.running` == a tool call with no result yet.
enum StepStatus: Equatable { case running, done, error }

/// A tool step's payload: the call identity/input plus its resolved result.
struct ToolStepPayload: Equatable {
    let toolUseID: String
    let name: String
    let input: JSONValue
    let result: ToolResultSummary
}

/// One node on an agent turn's timeline. `duration`/`tokens` are the telemetry
/// seam — always nil in the presentation-layer phase, populated later by a
/// first-class Step model without changing this shape.
struct TurnStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case thinking(String)
        case text(String)
        case tool(ToolStepPayload)
    }
    let id: String
    let kind: Kind
    let status: StepStatus
    let duration: Duration?
    let tokens: Int?
}

/// A top-level transcript row: a distinct user prompt bubble, or one agent turn
/// rendered as a step timeline.
enum TranscriptItem: Identifiable, Equatable {
    case userBubble(index: Int, message: AgentMessage)
    case agentTurn(id: String, steps: [TurnStep])

    var id: String {
        switch self {
        case .userBubble(let index, _): return "user-\(index)"
        case .agentTurn(let id, _): return id
        }
    }
}

/// Groups the flat `[AgentMessage]` transcript into per-turn timelines. Pure and
/// synchronous — safe to call every render.
enum TranscriptTimelineBuilder {
    /// A user message is a PROMPT bubble when it carries any `.text` or `.image`
    /// block. A user message with only `.toolResult` blocks is the tool-result
    /// carrier for the current agent turn, not a prompt.
    private static func isPromptBubble(_ message: AgentMessage) -> Bool {
        guard message.role == .user else { return false }
        return message.content.contains {
            switch $0 { case .text, .image: return true; default: return false }
        }
    }

    static func build(from messages: [AgentMessage]) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var currentSteps: [TurnStep] = []
        var turnStartIndex: Int?

        func flushTurn() {
            guard let start = turnStartIndex, !currentSteps.isEmpty else {
                currentSteps = []; turnStartIndex = nil; return
            }
            items.append(.agentTurn(id: "turn-\(start)", steps: currentSteps))
            currentSteps = []; turnStartIndex = nil
        }

        for (index, message) in messages.enumerated() {
            if isPromptBubble(message) {
                flushTurn()
                items.append(.userBubble(index: index, message: message))
                continue
            }
            // Assistant message, or a tool-result-only user message: contribute steps.
            if turnStartIndex == nil { turnStartIndex = index }
            for (blockIndex, block) in message.content.enumerated() {
                switch block {
                case .thinking(let t):
                    currentSteps.append(TurnStep(id: "\(index)-\(blockIndex)", kind: .thinking(t),
                                                 status: .done, duration: nil, tokens: nil))
                case .text(let t):
                    currentSteps.append(TurnStep(id: "\(index)-\(blockIndex)", kind: .text(t),
                                                 status: .done, duration: nil, tokens: nil))
                case .toolUse(let id, let name, let input):
                    let result = ToolResultLookup.summary(forToolUseID: id, after: index, in: messages)
                    let status: StepStatus = result.isPending ? .running : (result.isError ? .error : .done)
                    currentSteps.append(TurnStep(id: id,
                        kind: .tool(ToolStepPayload(toolUseID: id, name: name, input: input, result: result)),
                        status: status, duration: nil, tokens: nil))
                case .toolResult, .image:
                    break   // results are folded into their tool step; stray images ignored here
                }
            }
        }
        flushTurn()
        return items
    }
}
