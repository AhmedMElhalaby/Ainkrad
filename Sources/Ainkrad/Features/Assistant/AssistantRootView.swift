import SwiftUI
import AinkradAppKit

/// The Assistant Block's content: a transcript bound to the host's single
/// `AgentSession`, a collapsible "thinking" disclosure, and a composer. Reads
/// `AppEnvironment` directly (host-embedded built-in, like the Settings
/// sections) rather than going through `HostServices`.
struct AssistantRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    var showsHeader: Bool = true
    var autoFocusComposer: Bool = false
    @State private var draft = ""
    @State private var isThinkingExpanded = true
    @State private var modelPicker = AssistantModelPickerModel()

    var body: some View {
        let tokens = environment.themeManager.tokens
        let session = environment.agentSession

        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header(tokens: tokens)
            }

            transcript(session: session, tokens: tokens)

            AssistantComposerBar(
                session: session,
                tokens: tokens,
                modelPicker: modelPicker,
                draft: $draft,
                autoFocusOnAppear: autoFocusComposer
            )
        }
        .background {
            // Opacity-tinted surface. The blur (when enabled) is rendered by the
            // host behind the whole pane in `BlockView` — the same path every app
            // uses now — so this view only paints its opacity tint. At opacity 1.0
            // this is identical to the old opaque background.
            tokens.background.opacity(environment.appAppearanceStore.surfaceOpacity("assistant"))
        }
    }

    // MARK: - Header (new chat only)

    private func header(tokens: DesignTokens) -> some View {
        let session = environment.agentSession

        return HStack(spacing: 12) {
            Spacer(minLength: 0)
            newChatButton(session: session, tokens: tokens)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private func newChatButton(session: AgentSession, tokens: DesignTokens) -> some View {
        HoverNewChatButton(tokens: tokens) { session.reset() }
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
                            onDeny: { session.deny(reason: "Denied by user.") },
                            onApproveAlways: { session.approve(always: true) }
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
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo("streaming", anchor: .bottom) }
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
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }

            Text(message.text)
                .font(AinkradFont.display(13))
                .foregroundStyle(tokens.foreground.opacity(0.9))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(
                    ChamferShape(cut: AinkradRadius.md)
                        .fill(isUser ? tokens.accentPrimary.opacity(0.18) : tokens.surfaceElevated.opacity(0.4))
                )
                .shadow(color: (isUser ? tokens.accentPrimary : tokens.accentSecondary).opacity(0.12), radius: 6)

            if !isUser { Spacer(minLength: 40) }
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
                (Text(session.streamingText)
                    + Text(session.state == .streaming ? " ▍" : "")
                        .foregroundColor(tokens.accentSecondary))
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
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.4)))
        .shadow(color: tokens.accentSecondary.opacity(0.1), radius: 6)
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
            .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.accentTertiary.opacity(0.1)))
            .shadow(color: tokens.accentTertiary.opacity(0.15), radius: 6)
    }

}

/// New-chat control with a hover highlight (motion is first-class in the HUD).
private struct HoverNewChatButton: View {
    let tokens: DesignTokens
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12))
                .foregroundStyle(tokens.foreground.opacity(isHovering ? 0.9 : 0.6))
                .padding(6)
                .background(Circle().fill(tokens.surfaceElevated.opacity(isHovering ? 0.75 : 0.5)))
        }
        .buttonStyle(.plain)
        .help("New chat")
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
    }
}
