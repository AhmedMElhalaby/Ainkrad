import Foundation

enum AgentProvider: String, Codable, CaseIterable, Sendable { case claude, openai }

struct AgentModelConfig: Equatable, Sendable {
    var provider: AgentProvider
    var model: String          // e.g. "claude-opus-4-8" / "gpt-5"
    var effort: String         // "xhigh" (Claude only; ignored by OpenAI)
}

enum AgentEvent: Equatable, Sendable {
    case thinkingDelta(String)
    case textDelta(String)
    case toolUseStart(id: String, name: String)
    case toolInputDelta(id: String, partialJSON: String)
    case toolUseComplete(id: String, name: String, input: JSONValue)
    case done(stopReason: String?)
    case failed(String)        // human-readable, key already redacted
}

/// Single source of truth for the placeholder model-id lists shown in the
/// Assistant header and Settings — both views call this rather than keeping
/// their own copies in sync by hand.
enum AgentModelCatalog {
    static func models(for provider: AgentProvider) -> [String] {
        switch provider {
        case .claude: return ["claude-opus-4-8", "claude-sonnet-4-8", "claude-haiku-4-8"]
        case .openai: return ["gpt-5", "gpt-5-mini"]
        }
    }
}
