import Foundation
import Observation

/// The read-only chat loop that turns an `LLMProvider` into an agent: owns
/// the transcript, the in-flight streaming buffers, and the request
/// lifecycle state. No tool handling — that arrives in a later slice. The
/// Assistant UI (and, later, the ambient island) bind directly to this
/// `@Observable` state.
@MainActor
@Observable
final class AgentSession {
    enum State: Equatable {
        case idle
        case thinking
        case streaming
        case failed(String)
    }

    static let defaultPrompt = """
    You are Ainkrad's built-in assistant, embedded in a native macOS \
    developer workspace. Answer concisely and precisely.
    """

    private(set) var messages: [AgentMessage] = []
    private(set) var state: State = .idle
    private(set) var streamingText: String = ""
    private(set) var streamingThinking: String = ""

    /// The in-flight turn's task, exposed so tests can await settlement.
    /// Not part of the UI-facing contract.
    private(set) var currentTask: Task<Void, Never>?

    private let providerFor: (AgentProvider) -> LLMProvider
    private let connections: ConnectionStore
    private let config: AgentConfigStore
    private let context: AgentContextService
    private let basePrompt: String

    init(
        providerFor: @escaping (AgentProvider) -> LLMProvider,
        connections: ConnectionStore,
        config: AgentConfigStore,
        context: AgentContextService,
        basePrompt: String = AgentSession.defaultPrompt
    ) {
        self.providerFor = providerFor
        self.connections = connections
        self.config = config
        self.context = context
        self.basePrompt = basePrompt
    }

    func send(_ text: String) {
        // Re-entrancy guard: a read-only turn is single-flight. If one is
        // already in progress, ignore the new call entirely so the in-flight
        // Task's closure keeps exclusive ownership of the streaming buffers
        // (otherwise a second send would reset them mid-stream and corrupt the
        // appended transcript). The UI also disables the composer while busy,
        // but the model must be robust on its own.
        switch state {
        case .thinking, .streaming:
            return
        case .idle, .failed:
            break
        }

        messages.append(AgentMessage(role: .user, text: text))

        let modelConfig = config.current
        guard let apiKey = resolveAPIKey(for: modelConfig.provider) else {
            state = .failed("No API key configured for \(modelConfig.provider.rawValue)")
            return
        }

        let contextBlock = context.assembleContext()
        let system = contextBlock.isEmpty ? basePrompt : basePrompt + "\n\n" + contextBlock
        let provider = providerFor(modelConfig.provider)
        let history = messages

        state = .thinking
        streamingText = ""
        streamingThinking = ""

        currentTask = Task { [weak self] in
            guard let self else { return }
            let stream = provider.send(messages: history, system: system, tools: [], model: modelConfig, apiKey: apiKey)
            do {
                for try await event in stream {
                    self.handle(event)
                }
                // The stream finished without ever yielding `.done` or
                // `.failed` (dropped connection, or every event failed to
                // decode). Left alone, the session would stay wedged in
                // .thinking/.streaming forever and the re-entrancy guard
                // would make `send()` a permanent no-op. Finalize the turn
                // ourselves: commit whatever text arrived, or fail cleanly.
                switch self.state {
                case .thinking, .streaming:
                    if !self.streamingText.isEmpty {
                        self.messages.append(AgentMessage(role: .assistant, text: self.streamingText))
                        self.streamingText = ""
                        self.streamingThinking = ""
                        self.state = .idle
                    } else {
                        self.streamingText = ""
                        self.streamingThinking = ""
                        self.state = .failed("The response ended unexpectedly.")
                    }
                case .idle, .failed:
                    break
                }
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func reset() {
        currentTask?.cancel()
        currentTask = nil
        messages.removeAll()
        state = .idle
        streamingText = ""
        streamingThinking = ""
    }

    private func handle(_ event: AgentEvent) {
        switch event {
        case .thinkingDelta(let delta):
            streamingThinking += delta
            state = .thinking
        case .textDelta(let delta):
            streamingText += delta
            state = .streaming
        case .toolUseStart, .toolInputDelta, .toolUseComplete:
            break   // wired up by the tool-use loop in a later task
        case .done:
            if !streamingText.isEmpty {
                messages.append(AgentMessage(role: .assistant, text: streamingText))
            }
            streamingText = ""
            streamingThinking = ""
            state = .idle
        case .failed(let message):
            state = .failed(message)
        }
    }

    private func resolveAPIKey(for provider: AgentProvider) -> String? {
        let connectionProvider = ConnectionProvider(rawValue: provider.rawValue)
        guard let connectionProvider else { return nil }
        guard let match = connections.connections.first(where: { $0.provider == connectionProvider }) else {
            return nil
        }
        return connections.token(for: match)
    }
}
