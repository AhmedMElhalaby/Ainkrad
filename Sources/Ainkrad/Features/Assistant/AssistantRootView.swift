import SwiftUI
import AppKit
import AinkradAppKit

/// The Assistant Block's content: a transcript bound to the host's single
/// `AgentSession`, a collapsible "thinking" disclosure, and a composer. Reads
/// `AppEnvironment` directly (host-embedded built-in, like the Settings
/// sections) rather than going through `HostServices`.
struct AssistantRootView: View {
    // Not `private` — read from `AssistantRootView+Export.swift` (a `private`
    // member is file-scoped in Swift, so an extension in a different file
    // can't see it; same widening rationale `AssistantComposerBar` already
    // uses for its cross-file-read state).
    @Environment(AppEnvironment.self) var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    var showsHeader: Bool = true
    var autoFocusComposer: Bool = false
    @State private var draft = ""
    @State private var isSidebarVisible = false
    @State private var isThinkingExpanded = true
    @State private var modelPicker = AssistantModelPickerModel()
    @State private var hoveredTurnIndex: Int?
    // Not `private` — read from `AssistantRootView+Export.swift`.
    @Environment(\.ainkradToastCenter) var toastCenter
    @State private var isUsageDashboardPresented = false
    @State var isExportModalPresented = false
    @State private var isRunsPanelPresented = false
    @State private var isSchedulesPresented = false
    @State var redactionsText = ""

    var body: some View {
        let tokens = environment.themeManager.tokens
        let session = environment.agentSession
        let store = environment.assistantSessionStore

        HStack(spacing: 0) {
            if showsHeader && isSidebarVisible {
                AssistantHistorySidebar(
                    store: store,
                    tokens: tokens,
                    onNewChat: {
                        store.syncActive(messages: session.messages)
                        store.startNewSession()
                        session.reset()
                    },
                    onSelect: { id in
                        store.syncActive(messages: session.messages)
                        session.replaceMessages(store.activate(id))
                    }
                )
                .transition(reduceMotion ? .identity : .move(edge: .leading))
            }
            chatColumn(session: session, tokens: tokens)
        }
        .onChange(of: session.messages) { _, newValue in
            environment.assistantSessionStore.syncActive(messages: newValue)
        }
    }

    // MARK: - Chat column

    @ViewBuilder
    private func chatColumn(session: AgentSession, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header(tokens: tokens)
            }

            transcript(session: session, tokens: tokens)

            if case .awaitingApproval(let pending) = session.state {
                AssistantApprovalBar(
                    toolName: pending.call.name,
                    title: pending.preview.title,
                    tokens: tokens,
                    onDeny: { session.deny(reason: "Denied by user.") },
                    onApproveAlways: { session.approve(always: true) },
                    onApprove: { session.approve() }
                )
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }

            AssistantComposerBar(
                session: session,
                tokens: tokens,
                modelPicker: modelPicker,
                draft: $draft,
                autoFocusOnAppear: autoFocusComposer,
                isUsageDashboardPresented: $isUsageDashboardPresented,
                isRunsPanelPresented: $isRunsPanelPresented,
                isSchedulesPresented: $isSchedulesPresented,
                isExportModalPresented: $isExportModalPresented
            )
        }
        .animation(reduceMotion ? nil : AinkradMotion.present, value: session.state)
        .background {
            // Opacity-tinted surface. The blur (when enabled) is rendered by the
            // host behind the whole pane in `BlockView` — the same path every app
            // uses now — so this view only paints its opacity tint. At opacity 1.0
            // this is identical to the old opaque background.
            tokens.background.opacity(environment.appAppearanceStore.surfaceOpacity("assistant"))
        }
        .ainkradModal(isPresented: $isUsageDashboardPresented) {
            UsageDashboardView(tracker: environment.usageTracker, tokens: tokens)
        }
        .ainkradModal(isPresented: $isExportModalPresented) {
            exportModalContent
        }
        // Runs/Schedules are variable-length lists — bound them to a compact
        // centered card that scrolls internally (like Settings/Launcher),
        // never a full-height strip. `.ainkradModal` caps width (480); this
        // caps height.
        .ainkradModal(isPresented: $isRunsPanelPresented) {
            RunsPanelView(manager: environment.runManager, tokens: tokens)
                .frame(maxHeight: 520)
        }
        .ainkradModal(isPresented: $isSchedulesPresented) {
            ScheduleUIView(store: environment.scheduleStore)
                .frame(maxHeight: 520)
        }
    }

    // MARK: - Header (sidebar toggle)

    private func header(tokens: DesignTokens) -> some View {
        HStack(spacing: 12) {
            HoverSidebarToggle(tokens: tokens) {
                withAnimation(reduceMotion ? nil : AinkradMotion.present) {
                    isSidebarVisible.toggle()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    // MARK: - Transcript

    private var transcriptIsEmpty: Bool {
        environment.agentSession.messages.isEmpty
            && environment.agentSession.state == .idle
    }

    private var assistantTypography: AssistantTypography {
        AssistantTypography.resolve(
            family: environment.appAppearanceStore.fontFamily(AssistantApp.id),
            scale: environment.appAppearanceStore.fontScale(AssistantApp.id),
            globalFamily: environment.themeManager.uiFontFamily,
            globalScale: environment.themeManager.uiFontScale)
    }

    /// True during the brief `.callingTool` window before the assistant turn's
    /// `.toolUse` block is committed to `messages` — i.e. no pending card renders yet.
    /// Once the block commits, the per-message pending card takes over (Task 2).
    private func isCallingToolWithoutCard(_ session: AgentSession) -> Bool {
        guard case .callingTool = session.state else { return false }
        let hasToolUseBlock = session.messages.contains { msg in
            msg.content.contains { if case .toolUse = $0 { return true } else { return false } }
                && !msg.content.contains { if case .toolResult = $0 { return true } else { return false } }
        }
        return !hasToolUseBlock
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

                        if session.state == .thinking || session.state == .streaming
                            || isCallingToolWithoutCard(session) {
                            streamingBubble(session: session, tokens: tokens)
                                .id("streaming")
                                .transition(reduceMotion ? .identity : .opacity)
                        }

                        if case .awaitingApproval(let pending) = session.state {
                            ToolCallCardView(
                                toolName: pending.call.name,
                                title: pending.preview.title,
                                summary: pending.preview.summary,
                                diff: pending.preview.diff,
                                tokens: tokens,
                                pendingApproval: true
                            )
                            .id("approval")
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
                        }

                        if case .failed(let message) = session.state {
                            errorBubble(message, session: session, tokens: tokens)
                                .transition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .padding(14)
                    // The message array is mutated inside `AgentSession`, outside
                    // any `withAnimation`, so the per-turn `.transition` above has
                    // no transaction to ride. Binding an animation to the count
                    // gives newly-inserted rows their materialize transition.
                    // Gated so Reduce Motion inserts rows instantly.
                    .animation(reduceMotion ? nil : AinkradMotion.present, value: session.messages.count)
                    .animation(reduceMotion ? nil : AinkradMotion.present, value: session.state)
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
                    let result = ToolResultLookup.summary(forToolUseID: id, after: index, in: messages)
                    ToolCallCardView(
                        toolName: name,
                        title: ToolPresentation.humanize(name),
                        summary: result.text,
                        diff: nil,
                        tokens: tokens,
                        result: result
                    )
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
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
            // Only assistant turns with text show the hover copy button, so
            // only they drive the hovered-turn state — no dead writes for user
            // bubbles (which have no overlay).
            guard message.role == .assistant, !message.text.isEmpty else { return }
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
                    AssistantMarkdownText(text: message.text, tokens: tokens, typography: assistantTypography)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func streamingBubble(session: AgentSession, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.streamingThinking.isEmpty {
                thinkingDisclosure(session: session, tokens: tokens)
            }

            if session.state == .streaming || !session.streamingText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    AssistantMarkdownText(text: session.streamingText, tokens: tokens, typography: assistantTypography)
                    if session.state == .streaming {
                        StreamingCursor(tokens: tokens)
                    }
                }
            } else if session.streamingThinking.isEmpty {
                WorkingIndicator(tokens: tokens)
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

    private func errorBubble(_ message: String, session: AgentSession, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.accentTertiary)
                Text("Something went wrong")
                    .font(AinkradFont.display(12, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Spacer()
            }
            Text(message)
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .textSelection(.enabled)   // never truncated — an unreadable error is useless
            HStack {
                Spacer()
                ErrorRetryButton(tokens: tokens) { session.retryLastTurn() }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
        .overlay(alignment: .leading) {
            Rectangle().fill(tokens.accentTertiary).frame(width: 2)
        }
        .shadow(color: tokens.accentTertiary.opacity(0.14), radius: 7)
    }

}

/// Leading history-sidebar toggle with a hover highlight (motion is first-class in the HUD).
private struct HoverSidebarToggle: View {
    let tokens: DesignTokens
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 12))
                .foregroundStyle(tokens.foreground.opacity(isHovering ? 0.9 : 0.6))
                .padding(6)
                .background(Circle().fill(tokens.surfaceElevated.opacity(isHovering ? 0.75 : 0.5)))
        }
        .buttonStyle(.plain)
        .help("Toggle history")
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}

/// Retry control for the failed-turn error card. Hover-lit, chamfered — no native button chrome.
private struct ErrorRetryButton: View {
    let tokens: DesignTokens
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                Text("Retry").font(AinkradFont.display(11, weight: .medium))
            }
            .foregroundStyle(tokens.accentTertiary.opacity(isHovering ? 1 : 0.85))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(ChamferShape(cut: AinkradRadius.sm)
                .fill(tokens.accentTertiary.opacity(isHovering ? 0.18 : 0.1)))
        }
        .buttonStyle(.plain)
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

/// Breathing "working" affordance shown before the first streamed token and while a
/// tool call is spinning up before its card commits. Steady under Reduce Motion
/// (mirrors `StreamingCursor`).
private struct WorkingIndicator: View {
    let tokens: DesignTokens
    var label: String = "Thinking"
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            dots
            Text("\(label)…")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.45))
        }
    }

    // TimelineView-driven so the pulse actually runs — a one-shot `@State`
    // toggle with `.repeatForever(.animation(value:))` frequently never starts.
    // Same idiom as `StreamingCursor` above.
    @ViewBuilder private var dots: some View {
        if reduceMotion {
            HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in dot(0.7) } }
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        // ~1.6s breathe (2π·durationBase), 60° per-dot stagger.
                        let phase = t / AinkradMotion.durationBase + Double(i) * .pi / 3
                        dot(0.3 + 0.6 * (0.5 + 0.5 * sin(phase)))
                    }
                }
            }
        }
    }

    private func dot(_ opacity: Double) -> some View {
        Circle().fill(tokens.accentSecondary.opacity(opacity)).frame(width: 4, height: 4)
    }
}
