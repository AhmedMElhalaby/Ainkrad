import SwiftUI
import AppKit
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
    @State private var hoveredTurnIndex: Int?

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

    private var transcriptIsEmpty: Bool {
        environment.agentSession.messages.isEmpty
            && environment.agentSession.state == .idle
    }

    private func emptyState() -> some View {
        AinkradEmptyState(
            icon: "sparkles",
            title: "Ask the Assistant",
            message: "Type a message, or start with / for commands and @ to mention files.",
            actionTitle: nil,
            action: nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcript(session: AgentSession, tokens: DesignTokens) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if transcriptIsEmpty {
                    emptyState()
                        .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
                        ForEach(Array(session.messages.enumerated()), id: \.offset) { index, message in
                            bubble(for: message, at: index, in: session.messages, tokens: tokens)
                                .id(index)
                                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
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
                    // The message array is mutated inside `AgentSession`, outside
                    // any `withAnimation`, so the per-turn `.transition` above has
                    // no transaction to ride. Binding an animation to the count
                    // gives newly-inserted rows their materialize transition.
                    // Gated so Reduce Motion inserts rows instantly.
                    .animation(reduceMotion ? nil : AinkradMotion.present, value: session.messages.count)
                }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: session.messages.count) { _, _ in
                withAnimation(reduceMotion ? nil : AinkradMotion.present) { proxy.scrollTo("streaming", anchor: .bottom) }
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
                if case .image(let mediaType, let base64) = block {
                    imageChip(mediaType: mediaType, base64: base64, tokens: tokens)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if message.role == .assistant && !message.text.isEmpty {
                AssistantTurnCopyButton(text: message.text, isVisible: hoveredTurnIndex == index)
                    .padding(.trailing, 2)
            }
        }
        .onHover { isHovering in
            hoveredTurnIndex = isHovering ? index : (hoveredTurnIndex == index ? nil : hoveredTurnIndex)
        }
    }

    /// Renders an attached image as a thumbnail, falling back to a `[image]` chip
    /// when the base64 payload can't be decoded (e.g. malformed/truncated data).
    @ViewBuilder
    private func imageChip(mediaType: String, base64: String, tokens: DesignTokens) -> some View {
        if let data = Data(base64Encoded: base64), let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 160, maxHeight: 160)
                .clipShape(ChamferShape(cut: AinkradRadius.md))
        } else {
            Text("[image]")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.3)))
        }
    }

    private func textBubble(for message: AgentMessage, tokens: DesignTokens) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }

            Group {
                if isUser {
                    Text(message.text)
                        .font(AinkradFont.display(13))
                        .foregroundStyle(tokens.foreground.opacity(0.9))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.accentPrimary.opacity(0.18)))
                        .shadow(color: tokens.accentPrimary.opacity(0.12), radius: 6)
                } else {
                    AssistantMarkdownText(text: message.text, tokens: tokens)
                }
            }

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
                VStack(alignment: .leading, spacing: 2) {
                    AssistantMarkdownText(text: session.streamingText, tokens: tokens)
                    if session.state == .streaming {
                        StreamingCursor(tokens: tokens)
                    }
                }
            } else if session.streamingThinking.isEmpty {
                Text("Thinking…")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thinkingDisclosure(session: AgentSession, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : AinkradMotion.present) { isThinkingExpanded.toggle() }
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
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}

/// Copy-to-pasteboard for a whole assistant turn, revealed on hover.
private struct AssistantTurnCopyButton: View {
    let text: String
    /// Driven by the enclosing turn's hover region, not this button's own frame —
    /// the button sits at `opacity: 0` until the whole turn is hovered, so tying
    /// visibility to a local `.onHover` on the icon-sized frame made it undiscoverable.
    var isVisible: Bool
    @State private var copied = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        AinkradIconButton(systemName: copied ? "checkmark" : "doc.on.doc", size: 20, tooltip: "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        }
        .opacity(isVisible ? 0.8 : 0)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isVisible)
    }
}

/// Blinking caret shown at the tail of streaming output; steady under reduce-motion.
private struct StreamingCursor: View {
    let tokens: DesignTokens
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            caret(opacity: 1)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                caret(opacity: on ? 1 : 0.15)
            }
        }
    }

    private func caret(opacity: Double) -> some View {
        Text("▍").font(AinkradFont.display(13)).foregroundStyle(tokens.accentSecondary.opacity(opacity))
    }
}
