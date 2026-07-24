import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Renders one agent turn as a vertical rail: a leading tinted spine with a node
/// marker per step (`TimelineRailGutter`), and the step body (thinking disclosure
/// / markdown / tool card) to its right. Reuses `ToolCallCardView` for tool steps.
struct AgentTurnTimelineView: View {
    let steps: [TurnStep]
    let tokens: DesignTokens
    let typography: AssistantTypography
    let reduceMotion: Bool

    @State private var expandedThinking: Set<String> = []
    /// The text step currently hovered, keyed by step id — drives the per-step
    /// hover-to-copy affordance (restored from the pre-timeline bubble, which
    /// showed a copy button on hovered assistant turns).
    @State private var hoveredTextStep: String?
    /// Drives the one-shot staggered entrance. Held as view state keyed to the
    /// turn's `.id`, so committed turns cascade in once and don't replay on the
    /// frequent re-renders during streaming.
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.xl) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    TimelineRailGutter(status: step.status, tokens: tokens, reduceMotion: reduceMotion)
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

    @ViewBuilder
    private func stepBody(_ step: TurnStep) -> some View {
        switch step.kind {
        case .thinking(let text):
            TimelineThinkingRow(text: text, isExpanded: expandedThinking.contains(step.id),
                                tokens: tokens, reduceMotion: reduceMotion) {
                if expandedThinking.contains(step.id) { expandedThinking.remove(step.id) }
                else { expandedThinking.insert(step.id) }
            }
        case .text(let text):
            AssistantMarkdownText(text: text, tokens: tokens, typography: typography)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topTrailing) {
                    AssistantTurnCopyButton(text: text, isVisible: hoveredTextStep == step.id)
                        .padding(.trailing, 2)
                }
                .onHover { isHovering in
                    hoveredTextStep = isHovering ? step.id : (hoveredTextStep == step.id ? nil : hoveredTextStep)
                }
        case .tool(let payload):
            ToolCallCardView(
                toolName: payload.name,
                title: ToolPresentation.humanize(payload.name),
                summary: payload.result.text,
                diff: nil,
                tokens: tokens,
                result: payload.result)
        case .todo(let items):
            TodoChecklistView(items: items, tokens: tokens)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The in-flight turn's tail node: a pulsing `.running` rail node whose body is
/// the live streaming thinking/text (with a cursor), falling back to a working
/// indicator before any output arrives. Uses the same `TimelineRailGutter` /
/// `TimelineThinkingRow` as committed steps so the hand-off to the settled rail
/// is seamless.
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
            TimelineRailGutter(status: .running, tokens: tokens, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 8) {
                if !streamingThinking.isEmpty {
                    TimelineThinkingRow(text: streamingThinking, isExpanded: thinkingExpanded,
                                        tokens: tokens, reduceMotion: reduceMotion) { thinkingExpanded.toggle() }
                }
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
}
