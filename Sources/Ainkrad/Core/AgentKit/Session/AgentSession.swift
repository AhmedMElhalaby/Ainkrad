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

    /// Token usage accumulated from the most recently completed turn's `.usage`
    /// events. Consumed by `UsageTracker` (Task 9) to compute per-turn cost.
    private(set) var lastTurnUsage: TokenUsage = .zero

    /// The model ID actually attributed to the most recent `usage?.record(...)` call —
    /// the model failover/escalation ACTUALLY settled on, not necessarily the one
    /// `resolveTurn` originally picked. `nil` before any turn has settled.
    private(set) var lastUsageAttributedModel: String?

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
    private let agents: AgentStore?

    /// M7 Slice 5b wiring — every one of these is OPTIONAL and defaults to `nil`,
    /// mirroring the Slice 1 degrade-don't-crash pattern: with none of them injected
    /// the session behaves exactly as it did before this task (config.current model,
    /// single connection, no command interception, no usage/failover accounting).
    private let router: ModelRouter?
    private let usage: UsageTracker?
    private let runtime: RuntimeOptionsStore?
    private let commands: CommandRegistry?
    private let authProfiles: AuthProfileStore?
    /// Builds this turn's routable candidates (connection × model × catalog metadata).
    /// `@MainActor` and synchronous — live discovery (`LocalModelProbe`,
    /// `ModelCatalogService`) is async, so the provider of this closure is expected to
    /// have already cached/refreshed its candidate list elsewhere; `resolveTurn` only
    /// ever reads it once, synchronously, per turn.
    private let candidatesProvider: (@MainActor () -> [RouterCandidate])?
    /// `true` when the given connection is a LOCAL server (Ollama/LM Studio/other
    /// loopback) — same rule `LocalModelProbe.isLocal` uses. Consulted only to make a
    /// terminal connection-failure message actionable (Fix 3); `nil` (host not wired,
    /// e.g. older test doubles) falls back to the generic provider message unchanged.
    private let isLocalConnection: (@MainActor (Connection) -> Bool)?

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
        memory: MemoryService? = nil,
        agents: AgentStore? = nil,
        router: ModelRouter? = nil,
        usage: UsageTracker? = nil,
        runtime: RuntimeOptionsStore? = nil,
        commands: CommandRegistry? = nil,
        authProfiles: AuthProfileStore? = nil,
        candidatesProvider: (@MainActor () -> [RouterCandidate])? = nil,
        isLocalConnection: (@MainActor (Connection) -> Bool)? = nil
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
        self.agents = agents
        self.router = router
        self.usage = usage
        self.runtime = runtime
        self.commands = commands
        self.authProfiles = authProfiles
        self.candidatesProvider = candidatesProvider
        self.isLocalConnection = isLocalConnection
    }

    /// `images`, when non-empty, are attached as leading `.image` content
    /// blocks on the user message (M7 Slice 5c Task 22b — composer image
    /// drop). Defaults to `[]` so every pre-existing `send(_:)` call site
    /// (text-only) keeps compiling and behaving byte-for-byte unchanged.
    func send(_ text: String, images: [ImageAttachment] = []) {
        // Single dispatch path for slash commands (migrated from the old
        // `/remember `-only prefix intercept — see `BuiltinCommands.remember`).
        // A recognized command (including an unknown-`/foo`-surfaces-a-note case)
        // returns here without ever touching the transcript/provider path below.
        // Commands never carry images — an attached image always falls through
        // to the normal user-turn path below, even if the text happens to start
        // with `/` (there is nothing sensible for a slash command to do with it).
        if images.isEmpty, let commands {
            switch commands.run(text, on: self) {
            case .notACommand, .sendAsPrompt:
                break
            case .handled(let note):
                if let note { messages.append(AgentMessage(role: .assistant, text: note)) }
                return
            }
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

        var content: [AgentContentBlock] = images.map { .image(mediaType: $0.mediaType, base64: $0.base64) }
        content.append(.text(text))
        messages.append(AgentMessage(role: .user, content: content))

        state = .thinking
        streamingText = ""
        streamingThinking = ""

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.runConversation()
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

    /// Replaces the transcript wholesale — the seam `/compact` (Task 22a) applies
    /// `TranscriptCompactor`'s output through, without giving every caller direct
    /// mutation access to `messages`.
    func replaceMessages(_ newMessages: [AgentMessage]) {
        messages = newMessages
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

    // MARK: - Model resolution (Task 16)

    /// One turn's resolved sending target: which connection/model to use, the
    /// `RouterDecision` that produced it (`nil` when the router path wasn't taken —
    /// no router injected, or no candidates available), and the premium baseline
    /// the router avoided (feeds `UsageTracker`'s savings math).
    struct ResolvedTurn: Sendable {
        let connection: Connection?
        let modelConfig: AgentModelConfig
        let tier: ModelTier
        let baselineModel: String?
        let decision: RouterDecision?
        var model: String { modelConfig.model }
    }

    /// Resolution order: session pin (`/model`) → router (bounded by the active
    /// Agent's routing envelope; a disabled router or an unmatched pin falls back to
    /// the first candidate) → Agent default model → the standing `AgentConfigStore`
    /// model. The router path is OPT-IN: it only runs when both a `router` is
    /// injected AND `candidatesProvider` yields at least one candidate — with either
    /// missing, resolution degrades to the pre-Task-16 pin/default/config chain.
    private func resolveTurn() async -> ResolvedTurn {
        let pin = runtime?.options.pinnedModel
        let candidates = candidatesProvider?() ?? []

        if let router, !candidates.isEmpty {
            let routing = agents?.active.routing ?? AgentRouting()
            let lastMessage = messages.last(where: { $0.role == .user })?.text ?? ""
            // `needsTools` signals that THIS turn requires tool-use capability, not
            // merely that the registry has tools available (nearly always true for an
            // agentic host) — without deeper message-intent analysis, the conservative
            // default is `false`, so a plain/trivial message can still free-first route
            // to a local model even though tools exist in the registry.
            let signal = TaskSignal(estimatedInputTokens: lastMessage.count / 4,
                                    needsVision: false, needsTools: false,
                                    reasoningHeavy: false)
            let request = RouterRequest(signal: signal, lastMessage: lastMessage, routing: routing,
                                        candidates: candidates, userPinnedModel: pin, attempt: 0)
            let decision = await router.route(request)
            let connection = connections.connections.first(where: { $0.id == decision.candidate.connectionID })
                ?? activeConnection()
            let effort = effortString(capabilities: decision.candidate.descriptor.capabilities)
            return ResolvedTurn(connection: connection,
                                modelConfig: AgentModelConfig(model: decision.candidate.model, effort: effort),
                                tier: decision.tier, baselineModel: decision.baselineModel, decision: decision)
        }

        // Degraded path (no router, or no candidates to route over): pin, else the
        // active Agent's default, else the standing config model — exactly the
        // pre-Task-16 behavior when `agents`/`runtime` are also both nil.
        let fallbackModel = pin ?? agents?.active.defaultModel ?? config.current.model
        let connection = activeConnection()
        return ResolvedTurn(connection: connection,
                            modelConfig: AgentModelConfig(model: fallbackModel, effort: config.current.effort),
                            tier: .premium, baselineModel: nil, decision: nil)
    }

    /// `/think`'s honest-scope check (and `resolveTurn`'s effort wiring) both need
    /// "does this model actually respect an effort dial" — only `ClaudeProvider` sends
    /// `output_config.effort`; other kinds ignore it. `capabilities: nil` (the degraded
    /// resolution path, where there is no descriptor) is treated as capable, matching
    /// pre-Task-16 behavior of always honoring `config.current.effort` unconditionally.
    private func effortString(capabilities: ModelCapability?) -> String {
        guard let capabilities, capabilities.contains(.reasoningEffort) else { return config.current.effort }
        switch runtime?.options.thinkLevel {
        case "low": return "low"
        case "medium": return "medium"
        case "high": return "high"
        case "max": return "xhigh"
        default: return config.current.effort
        }
    }

    /// Best-effort "what model is this session currently pointed at" for slash
    /// commands (`/think`'s capability notice) — NOT a substitute for `resolveTurn`,
    /// which also consults the router; this is synchronous and router-unaware.
    func activeModelIDForCommands() -> String {
        runtime?.options.pinnedModel ?? agents?.active.defaultModel ?? config.current.model
    }

    /// Models to walk on a retryable send failure: the resolved model first, then any
    /// other candidate on the SAME connection (failover swaps model/key, never
    /// connection — see `FailoverController`'s doc comment on the `(model, keyIndex)`
    /// ordering it assumes).
    private func failoverModels(primary: String, connectionID: UUID) -> [String] {
        guard let candidatesProvider else { return [primary] }
        var ordered = [primary]
        for candidate in candidatesProvider() where candidate.connectionID == connectionID {
            if !ordered.contains(candidate.model) { ordered.append(candidate.model) }
        }
        return ordered
    }

    /// Records the turn's actual outcome — the model failover/escalation ACTUALLY
    /// used, not just the one `resolveTurn` originally picked — into the router's
    /// learning store and the usage ledger. Called once per settle (both the
    /// `.completed` and `.failed` exits of `runConversation`).
    private func recordSettlement(success: Bool, resolved: ResolvedTurn, usedModel: String) {
        if let decision = resolved.decision {
            let effective = decision.candidate.model == usedModel ? decision
                : RouterDecision(candidate: RouterCandidate(connectionID: decision.candidate.connectionID,
                                                            model: usedModel, descriptor: decision.candidate.descriptor),
                                 tier: decision.tier, reason: decision.reason,
                                 escalated: decision.escalated, baselineModel: decision.baselineModel)
            router?.recordOutcome(effective, success: success)
        }
        usage?.record(model: usedModel, usage: lastTurnUsage, baselineModel: resolved.baselineModel)
        lastUsageAttributedModel = usedModel
    }

    // MARK: - Loop

    private func runConversation() async {
        var iterations = 0
        let resolved = await resolveTurn()
        guard let connection = resolved.connection else {
            state = .failed("No connection configured. Add one in Assistant settings.")
            return
        }
        let allKeys = authProfiles?.keys(for: connection) ?? (connections.token(for: connection).map { [$0] } ?? [])
        if ProviderPreset.preset(id: connection.presetID).requiresKey && allKeys.isEmpty {
            state = .failed("No API key configured for \(connection.displayName)")
            return
        }
        let keys = allKeys.isEmpty ? [""] : allKeys

        let contextBlock = context.assembleContext()
        let agentInstructions = agents?.active.instructions ?? ""
        let promptHead = agentInstructions.isEmpty ? basePrompt : basePrompt + "\n\n" + agentInstructions
        let system = contextBlock.isEmpty ? promptHead : promptHead + "\n\n" + contextBlock
        let provider = providerFor(connection)

        var currentModel = resolved.modelConfig
        var currentApiKey = keys[0]
        var didOpeningFailover = false

        while true {
            // Cooperative cancellation: `reset()` cancels this task (and unwedges
            // any parked approval). Bail BEFORE re-sending so a reset never spawns
            // a zombie turn that resurrects the just-cleared transcript.
            if Task.isCancelled { return }

            let outcome: TurnOutcome
            if !didOpeningFailover {
                let models = failoverModels(primary: currentModel.model, connectionID: connection.id)
                let (result, usedModel, usedKey) = await runOneTurnWithFailover(
                    provider: provider, system: system, model: currentModel, models: models, keys: keys)
                outcome = result
                currentModel = AgentModelConfig(model: usedModel, effort: currentModel.effort)
                currentApiKey = usedKey
                didOpeningFailover = true
            } else {
                outcome = await runOneTurn(provider: provider, system: system, model: currentModel, apiKey: currentApiKey)
            }

            switch outcome {
            case .failed(let message):
                streamingText = ""
                streamingThinking = ""
                let isLocal = isLocalConnection?(connection) ?? false
                state = .failed(Self.actionableFailureMessage(message, connection: connection, isLocal: isLocal))
                recordSettlement(success: false, resolved: resolved, usedModel: currentModel.model)
                return
            case .completed:
                streamingText = ""
                streamingThinking = ""
                state = .idle
                recordSettlement(success: true, resolved: resolved, usedModel: currentModel.model)
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

    /// Turns a generic connection-failure message into an actionable one when the
    /// failing connection is LOCAL (Ollama/LM Studio/other loopback) — the common
    /// case being the server just isn't running, which the generic provider message
    /// ("Streaming failed: Could not connect to the server.") gives the user no way
    /// to act on. Any other failure (remote provider, or a local-connection failure
    /// that isn't connectivity-shaped, e.g. an auth error) passes through unchanged.
    /// Pure/testable: no I/O, no actor isolation required.
    nonisolated static func actionableFailureMessage(_ message: String, connection: Connection, isLocal: Bool) -> String {
        guard isLocal, message.lowercased().contains("connect") else { return message }
        return "Can't reach the local model server at \(connection.baseURL). " +
               "Start Ollama/LM Studio, or switch models (pick a model in the picker or /model <id>)."
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
        var turnUsage = TokenUsage.zero

        let stream = provider.send(messages: messages, system: system,
                                   tools: allowedSchemas(), model: model, apiKey: apiKey)
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
                case .usage(let u): turnUsage = turnUsage + u
                case .failed(let m): failure = m
                }
            }
        } catch {
            return .failed(error.localizedDescription)
        }
        lastTurnUsage = turnUsage

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

    /// Wraps the FIRST HTTP call of a user turn in a bounded failover walk over
    /// `models × keys`, advancing via `FailoverController.nextAttempt` (the same pure
    /// step function `FailoverController.run` uses) on a retryable failure — see
    /// `FailoverController.classify`. A non-retryable content/user error returns
    /// immediately (no cycling through every candidate for an error that would fail
    /// identically against all of them). Driven manually here, rather than through
    /// `FailoverController.run`'s closure-based driver, because that generic static
    /// function isn't actor-isolated — handing it a `@MainActor`-capturing closure
    /// (this method needs `self.runOneTurn`) trips Swift 6's strict-concurrency
    /// sending check. The bound (`models.count * keys.count` attempts, mirroring
    /// `run`'s own bound) is enforced identically. Follow-up tool-loop iterations
    /// within the same turn do NOT re-run failover — they reuse whichever `(model,
    /// key)` this call settled on.
    private func runOneTurnWithFailover(
        provider: LLMProvider, system: String, model: AgentModelConfig,
        models: [String], keys: [String]
    ) async -> (TurnOutcome, model: String, apiKey: String) {
        guard var current = FailoverController.nextAttempt(
            models: models, keys: keys, failedModel: nil, failedKeyIndex: nil, errorKind: .providerError
        ) else {
            return (.failed("no candidates configured"), model.model, keys.first ?? "")
        }

        let maxAttempts = max(models.count * keys.count, 1)
        var lastOutcome: TurnOutcome = .failed("no candidates configured")
        for _ in 0..<maxAttempts {
            let attemptModel = AgentModelConfig(model: current.model, effort: model.effort)
            let outcome = await runOneTurn(provider: provider, system: system,
                                           model: attemptModel, apiKey: keys[current.keyIndex])
            guard case .failed(let message) = outcome, let kind = FailoverController.classify(message) else {
                return (outcome, current.model, keys[current.keyIndex])
            }
            lastOutcome = outcome
            guard let next = FailoverController.nextAttempt(
                models: models, keys: keys,
                failedModel: current.model, failedKeyIndex: current.keyIndex, errorKind: kind
            ) else {
                return (outcome, current.model, keys[current.keyIndex])
            }
            current = next
        }
        return (lastOutcome, current.model, keys[current.keyIndex])
    }

    private func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = registry.tool(named: call.name) else {
            return ToolResult(content: "Unknown tool: \(call.name)", isError: true)
        }

        // Agent tool-policy pre-check, BEFORE the permission gate: this only
        // ever narrows — it can reject a call the gate would have allowed, but
        // can never approve one the gate would have blocked.
        if let policy = agents?.active.toolPolicy,
           !policy.allows(toolName: tool.name, permission: tool.permission) {
            return ToolResult(
                content: "The active agent (\(agents?.active.name ?? "")) is not permitted to use \(tool.name).",
                isError: true)
        }

        let decision = AgentPermissionPolicy.decide(
            toolPermission: tool.permission, toolName: tool.name,
            mode: effectiveMode(), allowlist: permissions.allowlist,
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

    /// Tool schemas presented to the provider, filtered to the active Agent's
    /// tool policy — a Plan Agent must not even SEE `edit_file` in its tool
    /// list. Narrows only: with no active `agents` store, every registry
    /// schema is presented, unchanged from pre-Task-4 behavior.
    private func allowedSchemas() -> [AgentToolSchema] {
        guard let policy = agents?.active.toolPolicy else { return registry.schemas }
        return registry.schemas.filter { schema in
            guard let tool = registry.tool(named: schema.name) else { return false }
            return policy.allows(toolName: tool.name, permission: tool.permission)
        }
    }

    /// Restrictiveness order for `AgentPermissionMode`, used by `effectiveMode()`
    /// to compute the most-restrictive-wins composition. Higher = more permissive.
    private static func rank(_ mode: AgentPermissionMode) -> Int {
        switch mode {
        case .ask: return 0
        case .autoApprove: return 1
        case .fullAuto: return 2
        }
    }

    /// The permission mode actually passed to `AgentPermissionPolicy.decide`:
    /// the MORE restrictive of the workspace mode and the active Agent's
    /// `permissionPosture` (when set). A profile can tighten the gate but can
    /// never loosen it beyond the workspace's own mode.
    private func effectiveMode() -> AgentPermissionMode {
        guard let posture = agents?.active.permissionPosture else { return permissions.mode }
        return Self.rank(posture) < Self.rank(permissions.mode) ? posture : permissions.mode
    }

    // MARK: - Test hooks (internal; exercised via @testable import in AinkradTests)

    func executeForTesting(_ call: ToolCall) async -> ToolResult { await execute(call) }
    func allowedSchemasForTesting() -> [AgentToolSchema] { allowedSchemas() }
    func effectiveModeForTesting() -> AgentPermissionMode { effectiveMode() }
    func resolveTurnForTesting() async -> ResolvedTurn { await resolveTurn() }
}
