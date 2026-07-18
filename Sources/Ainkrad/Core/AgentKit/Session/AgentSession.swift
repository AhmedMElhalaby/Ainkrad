import Foundation
import Observation

/// The tool-use agent loop: owns the transcript, in-flight streaming buffers,
/// the tool registry, and the per-turn approval gate. Runs
/// send → tool_use → execute (gated) → tool_result → repeat until end_turn.
@MainActor
@Observable
final class AgentSession {
    struct PendingApproval: Equatable, Sendable {
        let call: ToolCall
        let preview: ToolApprovalPreview
    }

    enum State: Equatable {
        case idle
        case thinking
        case streaming
        case callingTool(String)
        case awaitingApproval(PendingApproval)
        case failed(String)
    }

    static let defaultPrompt = """
    You are Ainkrad's built-in assistant, embedded in a native macOS \
    developer workspace. You can read and edit files using the provided tools. \
    Answer concisely and precisely.
    """

    private(set) var messages: [AgentMessage] = []
    private(set) var state: State = .idle
    private(set) var streamingText: String = ""
    private(set) var streamingThinking: String = ""

    /// Fired whenever a turn settles (the tool loop returns to `.idle` inside
    /// `runConversation`) — every-settle is the host's only reliable trigger,
    /// since there is no session-end signal. NOT fired by `reset()`'s `.idle`.
    var onSettled: (() -> Void)?

    /// The in-flight turn's task, exposed so tests can await settlement.
    /// Not part of the UI-facing contract.
    private(set) var currentTask: Task<Void, Never>?

    private let providerFor: (Connection) -> LLMProvider
    private let connections: ConnectionStore
    private let config: AgentConfigStore
    private let context: AgentContextService
    private let registry: AgentToolRegistry
    private let permissions: AgentPermissionStore
    private let basePrompt: String
    private let maxToolIterations: Int
    private let memory: MemoryService?

    private enum ApprovalOutcome { case approved, denied(String) }
    private var approvalContinuation: CheckedContinuation<ApprovalOutcome, Never>?

    init(
        providerFor: @escaping (Connection) -> LLMProvider,
        connections: ConnectionStore,
        config: AgentConfigStore,
        context: AgentContextService,
        registry: AgentToolRegistry,
        permissions: AgentPermissionStore,
        basePrompt: String = AgentSession.defaultPrompt,
        maxToolIterations: Int = 25,
        memory: MemoryService? = nil
    ) {
        self.providerFor = providerFor
        self.connections = connections
        self.config = config
        self.context = context
        self.registry = registry
        self.permissions = permissions
        self.basePrompt = basePrompt
        self.maxToolIterations = maxToolIterations
        self.memory = memory
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/remember ") {
            remember(String(trimmed.dropFirst("/remember ".count)))
            return
        }

        // Re-entrancy guard: a turn is single-flight. If one is already in
        // progress (thinking/streaming/tool/awaiting-approval), ignore the new
        // call so the in-flight Task keeps exclusive ownership of the streaming
        // buffers and transcript.
        switch state {
        case .thinking, .streaming, .callingTool, .awaitingApproval:
            return
        case .idle, .failed:
            break
        }

        messages.append(AgentMessage(role: .user, text: text))

        let modelConfig = config.current
        guard let connection = activeConnection() else {
            state = .failed("No connection configured. Add one in Assistant settings.")
            return
        }
        let apiKey = connections.token(for: connection) ?? ""
        if ProviderPreset.preset(id: connection.presetID).requiresKey && apiKey.isEmpty {
            state = .failed("No API key configured for \(connection.displayName)")
            return
        }

        let contextBlock = context.assembleContext()
        let system = contextBlock.isEmpty ? basePrompt : basePrompt + "\n\n" + contextBlock
        let provider = providerFor(connection)

        state = .thinking
        streamingText = ""
        streamingThinking = ""

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.runConversation(provider: provider, system: system,
                                       model: modelConfig, apiKey: apiKey)
        }
    }

    /// Resume a parked approval by allowing the pending tool call to run. When
    /// `always` is true, the pending call's tool is added to the auto-approve
    /// allowlist before resuming, so future calls to it skip the HUD.
    func approve(always: Bool = false) {
        guard let cont = approvalContinuation else { return }
        if always, case .awaitingApproval(let pending) = state {
            permissions.addToAllowlist(pending.call.name)
        }
        approvalContinuation = nil
        cont.resume(returning: .approved)
    }

    /// Resume a parked approval by denying it; `reason` is fed back to the model
    /// as an error `tool_result`.
    func deny(reason: String) {
        guard let cont = approvalContinuation else { return }
        approvalContinuation = nil
        cont.resume(returning: .denied(reason))
    }

    /// Persists a user-supplied fact to memory with `.remember` provenance.
    /// Backs the `/remember <text>` command intercepted at the top of `send`.
    func remember(_ fact: String) {
        memory?.write(fact, to: .memory, provenance: .remember)
    }

    func reset() {
        currentTask?.cancel()
        currentTask = nil
        // Unwedge any parked approval so the in-flight loop unwinds cleanly.
        if let cont = approvalContinuation {
            approvalContinuation = nil
            cont.resume(returning: .denied("cancelled"))
        }
        messages.removeAll()
        state = .idle
        streamingText = ""
        streamingThinking = ""
    }

    // MARK: - Loop

    private func runConversation(provider: LLMProvider, system: String,
                                 model: AgentModelConfig, apiKey: String) async {
        var iterations = 0
        while true {
            // Cooperative cancellation: `reset()` cancels this task (and unwedges
            // any parked approval). Bail BEFORE re-sending so a reset never spawns
            // a zombie turn that resurrects the just-cleared transcript.
            if Task.isCancelled { return }
            let outcome = await runOneTurn(provider: provider, system: system, model: model, apiKey: apiKey)
            switch outcome {
            case .failed(let message):
                streamingText = ""
                streamingThinking = ""
                state = .failed(message)
                return
            case .completed:
                streamingText = ""
                streamingThinking = ""
                state = .idle
                settled()
                return
            case .toolCalls(let calls, let assistantText):
                iterations += 1
                if iterations > maxToolIterations {
                    messages.append(AgentMessage(role: .assistant,
                        text: (assistantText.isEmpty ? "" : assistantText + "\n\n") +
                              "Stopped: reached the \(maxToolIterations)-step tool limit."))
                    state = .idle
                    settled()
                    return
                }
                // Commit the assistant turn (text + tool_use blocks).
                var assistantBlocks: [AgentContentBlock] = assistantText.isEmpty ? [] : [.text(assistantText)]
                assistantBlocks.append(contentsOf: calls.map { .toolUse(id: $0.id, name: $0.name, input: $0.input) })
                messages.append(AgentMessage(role: .assistant, content: assistantBlocks))

                // Execute each call behind the gate; gather results into one user turn.
                var resultBlocks: [AgentContentBlock] = []
                for call in calls {
                    let result = await execute(call)
                    // A reset during a parked approval cancels this task while
                    // suspended inside `execute`. Bail before recording the
                    // (denied) result so `messages` stays cleared and `.idle` holds.
                    if Task.isCancelled { return }
                    resultBlocks.append(.toolResult(toolUseID: call.id, content: result.content, isError: result.isError))
                }
                messages.append(AgentMessage(role: .user, content: resultBlocks))
                streamingText = ""
                streamingThinking = ""
                // loop: re-send with the appended results
            }
        }
    }

    private enum TurnOutcome {
        case completed
        case failed(String)
        case toolCalls([ToolCall], assistantText: String)
    }

    private func runOneTurn(provider: LLMProvider, system: String,
                            model: AgentModelConfig, apiKey: String) async -> TurnOutcome {
        state = .thinking
        streamingText = ""
        streamingThinking = ""
        var pendingCalls: [ToolCall] = []
        var failure: String?
        var sawDone = false

        let stream = provider.send(messages: messages, system: system,
                                   tools: registry.schemas, model: model, apiKey: apiKey)
        do {
            for try await event in stream {
                switch event {
                case .thinkingDelta(let d): streamingThinking += d; state = .thinking
                case .textDelta(let d): streamingText += d; state = .streaming
                case .toolUseStart(_, let name): state = .callingTool(name)
                case .toolInputDelta: break
                case .toolUseComplete(let id, let name, let input):
                    pendingCalls.append(ToolCall(id: id, name: name, input: input))
                case .done: sawDone = true
                case .failed(let m): failure = m
                }
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        if let failure { return .failed(failure) }
        if !pendingCalls.isEmpty {
            return .toolCalls(pendingCalls, assistantText: streamingText)
        }
        // No tool calls: commit any assistant text, then settle.
        if !streamingText.isEmpty {
            messages.append(AgentMessage(role: .assistant, text: streamingText))
            return .completed
        }
        // Empty text. A clean `.done` (tool-less/text-less end_turn) settles to
        // idle; a stream that ended WITHOUT `.done` is a wedge we finalize as a
        // failure so the re-entrancy guard never stays stuck.
        return sawDone ? .completed : .failed("The response ended unexpectedly.")
    }

    private func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = registry.tool(named: call.name) else {
            return ToolResult(content: "Unknown tool: \(call.name)", isError: true)
        }
        let decision = AgentPermissionPolicy.decide(
            toolPermission: tool.permission, toolName: tool.name,
            mode: permissions.mode, allowlist: permissions.allowlist,
            gateReads: permissions.gateReads, isIrreversible: tool.isIrreversible(call.input))

        if decision == .requireApproval {
            let preview = tool.approvalPreview(call.input)
            state = .awaitingApproval(PendingApproval(call: call, preview: preview))
            let outcome = await withCheckedContinuation { (cont: CheckedContinuation<ApprovalOutcome, Never>) in
                approvalContinuation = cont
            }
            if case .denied(let reason) = outcome {
                return ToolResult(content: reason, isError: true)
            }
        }

        state = .callingTool(call.name)
        return await registry.run(call)
    }

    /// Runs the cheap rule-based consolidation pass and notifies observers
    /// whenever a turn settles to `.idle` (both terminal points inside
    /// `runConversation` — not `reset()`, which is a discard, not a settle).
    private func settled() {
        if let memory { MemoryConsolidator.consolidate(memory) }
        onSettled?()
    }

    /// The active connection: the configured one, else the first connection.
    private func activeConnection() -> Connection? {
        if let id = config.activeConnectionID,
           let match = connections.connections.first(where: { $0.id == id }) {
            return match
        }
        return connections.connections.first
    }
}
