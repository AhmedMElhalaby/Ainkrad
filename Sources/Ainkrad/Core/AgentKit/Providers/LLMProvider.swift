import Foundation

@MainActor protocol LLMProvider {
    /// Streams the assistant turn. `system` is the assembled system prompt+context.
    func send(messages: [AgentMessage], system: String, model: AgentModelConfig, apiKey: String) -> AsyncThrowingStream<AgentEvent, Error>
}
