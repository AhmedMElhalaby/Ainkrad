import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Renders one agent turn as a vertical rail: a leading tinted spine with a node
/// marker per step, and the step body (thinking disclosure / markdown / tool card)
/// to its right. Reuses `ToolCallCardView` for tool steps.
struct AgentTurnTimelineView: View {
    let steps: [TurnStep]
    let tokens: DesignTokens
    let typography: AssistantTypography
    let reduceMotion: Bool

    @State private var expandedThinking: Set<String> = []
    /// Drives the one-shot staggered entrance. Held as view state keyed to the
    /// turn's `.id`, so committed turns cascade in once and don't replay on the
    /// frequent re-renders during streaming.
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.xl) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    railGutter(for: step)
                    stepBody(step)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Staggered fade + rise as the turn materializes; instant under
                // Reduce Motion. Delay scales with the step's position so the
                // rail draws top-to-bottom.
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 10)
                .animation(reduceMotion ? nil : AinkradMotion.present.delay(Double(index) * 0.07), value: appeared)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { appeared = true }
    }

    // The spine + node marker. The spine runs the full height so consecutive
    // steps read as one connected rail; the marker sits at the step's top.
    private func railGutter(for step: TurnStep) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(tokens.accentPrimary.opacity(0.25))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            TimelineNodeMarker(status: step.status, tint: tokens.accentPrimary,
                               errorColor: tokens.accentTertiary, reduceMotion: reduceMotion)
                .padding(.top, 3)
        }
        .frame(width: 10)
    }

    @ViewBuilder
    private func stepBody(_ step: TurnStep) -> some View {
        switch step.kind {
        case .thinking(let text):
            thinkingStep(id: step.id, text: text)
        case .text(let text):
            AssistantMarkdownText(text: text, tokens: tokens, typography: typography)
        case .tool(let payload):
            ToolCallCardView(
                toolName: payload.name,
                title: ToolPresentation.humanize(payload.name),
                summary: payload.result.text,
                diff: nil,
                tokens: tokens,
                result: payload.result)
        }
    }

    private func thinkingStep(id: String, text: String) -> some View {
        let isExpanded = expandedThinking.contains(id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : AinkradMotion.present) {
                    if isExpanded { expandedThinking.remove(id) } else { expandedThinking.insert(id) }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 9))
                    Text("Thinking").font(AinkradFont.display(11, weight: .medium)).kerning(1)
                }
                .foregroundStyle(tokens.accentSecondary.opacity(0.85))
            }
            .buttonStyle(.plain)
            if isExpanded {
                Text(text)
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                    .textSelection(.enabled)
            }
        }
    }
}

/// The in-flight turn's tail node: a pulsing `.running` rail node whose body is
/// the live streaming thinking/text (with a cursor), falling back to a working
/// indicator before any output arrives. Visually identical to a committed
/// running node so the hand-off to the settled rail is seamless.
struct LiveStepView: View {
    let streamingText: String
    let streamingThinking: String
    let isStreaming: Bool
    let tokens: DesignTokens
    let typography: AssistantTypography
    let reduceMotion: Bool
    @State private var thinkingExpanded = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .top) {
                Rectangle().fill(tokens.accentPrimary.opacity(0.25)).frame(width: 1).frame(maxHeight: .infinity)
                TimelineNodeMarker(status: .running, tint: tokens.accentPrimary,
                                   errorColor: tokens.accentTertiary, reduceMotion: reduceMotion)
                    .padding(.top, 3)
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 8) {
                if !streamingThinking.isEmpty { liveThinking }
                if isStreaming || !streamingText.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        AssistantMarkdownText(text: streamingText, tokens: tokens, typography: typography)
                        if isStreaming { StreamingCursor(tokens: tokens) }
                    }
                } else if streamingThinking.isEmpty {
                    WorkingIndicator(tokens: tokens)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var liveThinking: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : AinkradMotion.present) { thinkingExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: thinkingExpanded ? "chevron.down" : "chevron.right").font(.system(size: 9))
                    Text("Thinking").font(AinkradFont.display(11, weight: .medium)).kerning(1)
                }
                .foregroundStyle(tokens.accentSecondary.opacity(0.85))
            }
            .buttonStyle(.plain)
            if thinkingExpanded {
                Text(streamingThinking).font(AinkradFont.mono(11)).foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
    }
}
