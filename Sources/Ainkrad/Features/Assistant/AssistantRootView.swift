import SwiftUI

/// The Assistant Block's content: a transcript bound to the host's single
/// `AgentSession`, a collapsible "thinking" disclosure, and a composer. Reads
/// `AppEnvironment` directly (host-embedded built-in, like the Settings
/// sections) rather than going through `HostServices`.
struct AssistantRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var draft = ""
    @State private var isThinkingExpanded = true

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
        let configStore = environment.agentConfigStore
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

            NeonSegmentedPicker(
                items: AgentProvider.allCases,
                selection: Binding(
                    get: { configStore.current.provider },
                    set: { configStore.setProvider($0) }
                ),
                label: providerTitle,
                tokens: tokens
            )
            .frame(width: 140)

            modelMenu(tokens: tokens)

            newChatButton(session: session, tokens: tokens)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
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

    private func modelMenu(tokens: DesignTokens) -> some View {
        let configStore = environment.agentConfigStore

        return Menu {
            ForEach(modelOptions(for: configStore.current.provider), id: \.self) { model in
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

    private func modelOptions(for provider: AgentProvider) -> [String] {
        AgentModelCatalog.models(for: provider)
    }

    private func providerTitle(_ provider: AgentProvider) -> String {
        switch provider {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        }
    }

    // MARK: - Transcript

    private func transcript(session: AgentSession, tokens: DesignTokens) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(session.messages.enumerated()), id: \.offset) { index, message in
                        bubble(for: message, tokens: tokens)
                            .id(index)
                    }

                    if session.state == .thinking || session.state == .streaming {
                        streamingBubble(session: session, tokens: tokens)
                            .id("streaming")
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

    private func bubble(for message: AgentMessage, tokens: DesignTokens) -> some View {
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
        let isBusy = session.state == .thinking || session.state == .streaming

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

    private func send(session: AgentSession) {
        let isBusy = session.state == .thinking || session.state == .streaming
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
