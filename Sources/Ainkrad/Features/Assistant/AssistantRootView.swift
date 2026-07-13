import SwiftUI

/// The Assistant Block's content: a transcript bound to the host's single
/// `AgentSession`, a collapsible "thinking" disclosure, and a composer. Reads
/// `AppEnvironment` directly (host-embedded built-in, like the Settings
/// sections) rather than going through `HostServices`.
struct AssistantRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var draft = ""
    @State private var isThinkingExpanded = true
    @State private var discoveredModels: [UUID: [String]] = [:]

    var body: some View {
        let tokens = environment.themeManager.tokens
        let session = environment.agentSession

        VStack(alignment: .leading, spacing: 0) {
            header(tokens: tokens)

            hairline(tokens: tokens)

            transcript(session: session, tokens: tokens)

            hairline(tokens: tokens)

            composer(session: session, tokens: tokens)
        }
        .background(tokens.background)
    }

    // MARK: - Header (provider + model)

    private func header(tokens: DesignTokens) -> some View {
        let session = environment.agentSession

        return HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(tokens.accentSecondary)
            Text("ASSISTANT")
                .font(AinkradFont.display(11, weight: .semibold))
                .kerning(2.5)
                .foregroundStyle(tokens.foreground.opacity(0.6))

            Spacer(minLength: 12)

            connectionMenu(tokens: tokens)

            modelMenu(tokens: tokens)

            NeonSegmentedPicker(
                items: AgentPermissionMode.allCases,
                selection: Binding(
                    get: { environment.agentPermissionStore.mode },
                    set: { environment.agentPermissionStore.setMode($0) }
                ),
                label: permissionTitle,
                tokens: tokens
            )
            .frame(width: 150)

            newChatButton(session: session, tokens: tokens)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .onAppear { if let c = activeConnection() { refreshModels(for: c) } }
        .onChange(of: activeConnection()?.id) { _, _ in
            if let c = activeConnection() { refreshModels(for: c) }
        }
    }

    private func refreshModels(for connection: Connection) {
        let store = environment.connectionStore
        let svc = environment.modelCatalogService
        let preset = ProviderPreset.preset(id: connection.presetID)
        let key = store.token(for: connection) ?? ""
        Task {
            let result = await svc.modelsResult(kind: connection.kind, baseURL: connection.baseURL,
                                                apiKey: key, curatedFallback: preset.curatedModels)
            discoveredModels[connection.id] = result.models
            if result.isLive {
                reconcileModelIfNeeded(for: connection, availableModels: result.models)
            }
        }
    }

    /// If the active connection's active model isn't valid for it (e.g. still the
    /// Claude default on a freshly-added non-Claude connection), fall back to the
    /// first available model for that connection. Never overrides an explicitly
    /// chosen model that IS in the list. Only called when the model list was
    /// genuinely fetched live — never on a curated fallback from a failed fetch.
    private func reconcileModelIfNeeded(for connection: Connection, availableModels: [String]) {
        let configStore = environment.agentConfigStore
        guard activeConnection()?.id == connection.id else { return }
        guard !availableModels.isEmpty, !availableModels.contains(configStore.current.model) else { return }
        configStore.setModel(availableModels[0])
    }

    private func newChatButton(session: AgentSession, tokens: DesignTokens) -> some View {
        Button {
            session.reset()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .padding(6)
                .background(Circle().fill(tokens.surfaceElevated.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .help("New chat")
    }

    private func connectionMenu(tokens: DesignTokens) -> some View {
        let configStore = environment.agentConfigStore
        let store = environment.connectionStore
        let active = activeConnection()

        return Menu {
            if store.connections.isEmpty {
                Text("No connections")
            } else {
                ForEach(store.connections) { connection in
                    Button(connection.displayName) {
                        configStore.setActiveConnectionID(connection.id)
                        configStore.setModel(ProviderPreset.preset(id: connection.presetID).curatedModels.first ?? configStore.current.model)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(active?.displayName ?? "No connection")
                    .font(AinkradFont.display(11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundStyle(tokens.foreground.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(tokens.surfaceElevated.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func modelMenu(tokens: DesignTokens) -> some View {
        let configStore = environment.agentConfigStore

        return Menu {
            ForEach(modelOptions(for: activeConnection()), id: \.self) { model in
                Button(model) { configStore.setModel(model) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(configStore.current.model)
                    .font(AinkradFont.mono(11))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundStyle(tokens.foreground.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(tokens.surfaceElevated.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func activeConnection() -> Connection? {
        let store = environment.connectionStore
        if let id = environment.agentConfigStore.activeConnectionID,
           let match = store.connections.first(where: { $0.id == id }) { return match }
        return store.connections.first
    }

    private func modelOptions(for connection: Connection?) -> [String] {
        guard let connection else { return [] }
        return discoveredModels[connection.id] ?? ProviderPreset.preset(id: connection.presetID).curatedModels
    }

    private func permissionTitle(_ mode: AgentPermissionMode) -> String {
        switch mode {
        case .ask: return "Ask"
        case .autoApprove: return "Auto"
        case .fullAuto: return "Full-auto"
        }
    }

    // MARK: - Transcript

    private func transcript(session: AgentSession, tokens: DesignTokens) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(session.messages.enumerated()), id: \.offset) { index, message in
                        bubble(for: message, at: index, in: session.messages, tokens: tokens)
                            .id(index)
                    }

                    if session.state == .thinking || session.state == .streaming {
                        streamingBubble(session: session, tokens: tokens)
                            .id("streaming")
                    }

                    if case .awaitingApproval(let pending) = session.state {
                        ToolCallCardView(
                            title: pending.preview.title,
                            summary: pending.preview.summary,
                            diff: pending.preview.diff,
                            tokens: tokens,
                            onApprove: { session.approve() },
                            onDeny: { session.deny(reason: "Denied by user.") }
                        )
                        .id("approval")
                    }

                    if case .callingTool(let name) = session.state {
                        Text("Running \(name)…")
                            .font(AinkradFont.display(12))
                            .foregroundStyle(tokens.foreground.opacity(0.45))
                    }

                    if case .failed(let message) = session.state {
                        errorBubble(message, tokens: tokens)
                    }
                }
                .padding(14)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: session.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("streaming", anchor: .bottom) }
            }
            .onChange(of: session.streamingText) { _, _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func bubble(for message: AgentMessage, at index: Int, in messages: [AgentMessage], tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.text.isEmpty {
                textBubble(for: message, tokens: tokens)
            }

            ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                if case .toolUse(let id, let name, _) = block {
                    ToolCallCardView(
                        title: name,
                        summary: toolResultSummary(for: id, after: index, in: messages),
                        diff: nil,
                        tokens: tokens
                    )
                }
            }
        }
    }

    private func textBubble(for message: AgentMessage, tokens: DesignTokens) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.text)
                .font(AinkradFont.display(13))
                .foregroundStyle(tokens.foreground.opacity(0.9))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(message.role == .user
                              ? tokens.accentPrimary.opacity(0.18)
                              : tokens.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1)
                )

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    /// Finds the `.toolResult` matching a tool_use id in the following message(s)
    /// and returns its content as the card summary, or a muted fallback.
    private func toolResultSummary(for id: String, after index: Int, in messages: [AgentMessage]) -> String {
        for message in messages[(index + 1)...] {
            for block in message.content {
                if case .toolResult(let toolUseID, let content, _) = block, toolUseID == id {
                    return content
                }
            }
        }
        return "Running…"
    }

    @ViewBuilder
    private func streamingBubble(session: AgentSession, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.streamingThinking.isEmpty {
                thinkingDisclosure(session: session, tokens: tokens)
            }

            if session.state == .streaming || !session.streamingText.isEmpty {
                Text(session.streamingText)
                    .font(AinkradFont.display(13))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
            } else if session.streamingThinking.isEmpty {
                Text("Thinking…")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    private func thinkingDisclosure(session: AgentSession, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isThinkingExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("Thinking")
                        .font(AinkradFont.display(11, weight: .medium))
                        .kerning(1)
                }
                .foregroundStyle(tokens.accentSecondary.opacity(0.85))
            }
            .buttonStyle(.plain)

            if isThinkingExpanded {
                Text(session.streamingThinking)
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
    }

    private func errorBubble(_ message: String, tokens: DesignTokens) -> some View {
        Text(message)
            .font(AinkradFont.display(12))
            .foregroundStyle(tokens.accentTertiary)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentTertiary.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Composer

    private func composer(session: AgentSession, tokens: DesignTokens) -> some View {
        let isBusy = Self.isBusy(session.state)

        return HStack(spacing: 10) {
            TextField("Message Assistant…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AinkradFont.display(13))
                .foregroundStyle(tokens.foreground)
                .tint(tokens.accentSecondary)
                .disabled(isBusy)
                .lineLimit(1...5)
                .onSubmit { send(session: session) }

            Button {
                send(session: session)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend(isBusy: isBusy) ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!canSend(isBusy: isBusy))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
        .padding(14)
    }

    private func canSend(isBusy: Bool) -> Bool {
        !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isBusy(_ state: AgentSession.State) -> Bool {
        switch state {
        case .thinking, .streaming, .callingTool, .awaitingApproval: return true
        case .idle, .failed: return false
        }
    }

    private func send(session: AgentSession) {
        let isBusy = Self.isBusy(session.state)
        guard canSend(isBusy: isBusy) else { return }
        let text = draft
        draft = ""
        session.send(text)
    }

    private func hairline(tokens: DesignTokens) -> some View {
        LinearGradient(
            colors: [.clear, tokens.accentPrimary.opacity(0.4), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}
