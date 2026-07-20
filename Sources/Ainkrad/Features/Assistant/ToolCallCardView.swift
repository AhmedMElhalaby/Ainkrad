import SwiftUI
import AinkradAppKit

/// Inline transcript card for a tool call. In `.awaitingApproval` it shows the
/// preview (with a diff for edits) and Approve/Deny; committed calls render a
/// per-tool identity (icon/tint), a success/error/pending verdict, and are
/// compact by default with a tap-to-expand body. Seamless surface, no
/// separator lines — matches the streaming/error bubbles.
struct ToolCallCardView: View {
    let title: String
    let summary: String
    let diff: String?
    let tokens: DesignTokens
    var onApprove: (() -> Void)?
    var onDeny: (() -> Void)?
    var onApproveAlways: (() -> Void)?
    /// Present for committed transcript cards; nil for the approval card.
    var result: ToolResultSummary?

    @State private var isExpanded = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var presentation: ToolPresentation { ToolPresentation.for(toolName: title) }
    private var tint: Color { presentation.tint == .primary ? tokens.accentPrimary : tokens.accentSecondary }
    private var isError: Bool { result?.isError == true }
    private var isPending: Bool { result?.isPending == true }
    private var isApproval: Bool { onApprove != nil || onDeny != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded || isApproval || isError {
                bodyContent
            }
            if isApproval { approvalButtons }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
        .overlay {
            if isApproval {
                ChamferShape(cut: AinkradRadius.md)
                    .stroke(tokens.accentPrimary.opacity(0.6), lineWidth: 1)
            }
        }
        .overlay(alignment: .leading) {
            if isError {
                Rectangle().fill(tokens.accentTertiary).frame(width: 2)
            }
        }
        .shadow(color: (isError ? tokens.accentTertiary : tint).opacity(0.14), radius: 7)
        .contentShape(Rectangle())
        .onTapGesture {
            guard result != nil, !isApproval else { return }
            withAnimation(reduceMotion ? nil : AinkradMotion.present) { isExpanded.toggle() }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: presentation.icon)
                .font(.system(size: 11))
                .foregroundStyle(isError ? tokens.accentTertiary : tint)
            Text(presentation.label)
                .font(AinkradFont.display(12, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Spacer()
            verdictGlyph
            if result != nil && !isApproval && !isError {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(tokens.foreground.opacity(0.4))
            }
        }
    }

    @ViewBuilder private var verdictGlyph: some View {
        if isPending {
            Text("Running…").font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
        } else if isError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundStyle(tokens.accentTertiary)
        } else if result != nil {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tokens.accentSecondary.opacity(0.7))
        }
    }

    @ViewBuilder private var bodyContent: some View {
        if !summary.isEmpty && !isPending {
            Text(summary)
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(isError ? 0.85 : 0.6))
                .lineLimit(isError ? nil : (isExpanded ? nil : 2))   // errors never truncated away
                .textSelection(.enabled)
        }
        if let diff, !diff.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(diffGutterAttributed(diff)).font(AinkradFont.mono(11)).textSelection(.enabled)
            }
            .frame(maxHeight: 200)
        }
    }

    private var approvalButtons: some View {
        HStack(spacing: 8) {
            Spacer()
            ToolCardButton(title: "Deny", tint: tokens.accentTertiary, filled: false, tokens: tokens) { onDeny?() }
            if let onApproveAlways {
                ToolCardButton(title: "Allow always", tint: tokens.accentSecondary, filled: false, tokens: tokens) { onApproveAlways() }
            }
            ToolCardButton(title: "Approve", tint: tokens.accentPrimary, filled: true, tokens: tokens) { onApprove?() }
        }
    }

    private func diffGutterAttributed(_ diff: String) -> AttributedString {
        var out = AttributedString()
        for (i, line) in diff.components(separatedBy: "\n").enumerated() {
            let sign = line.first
            let gutter = sign == "+" ? "+ " : (sign == "-" ? "- " : "  ")
            var seg = AttributedString((i == 0 ? "" : "\n") + gutter + line.dropFirst(sign == "+" || sign == "-" ? 1 : 0))
            if sign == "+" { seg.foregroundColor = tokens.accentSecondary }
            else if sign == "-" { seg.foregroundColor = tokens.accentTertiary }
            else { seg.foregroundColor = tokens.foreground.opacity(0.5) }
            out += seg
        }
        return out
    }
}

/// A tool-card action button with a hover highlight. `filled` renders the
/// primary (Approve) affordance as a solid accent chip; the others are text
/// buttons that gain a soft tinted fill on hover.
private struct ToolCardButton: View {
    let title: String
    let tint: Color
    let filled: Bool
    let tokens: DesignTokens
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AinkradFont.display(12, weight: filled ? .semibold : .regular))
                .foregroundStyle(filled ? tint.contrastingText : tint.opacity(isHovering ? 1 : 0.85))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(
                    ChamferShape(cut: AinkradRadius.sm)
                        .fill(filled ? tint.opacity(0.9) : tint.opacity(isHovering ? 0.18 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
}
