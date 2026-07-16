import SwiftUI
import AinkradAppKit

/// Inline transcript card for a tool call. In `.awaitingApproval` it shows the
/// preview (with a diff for edits) and Approve/Deny; committed calls render as a
/// compact, muted summary. Seamless surface, no separator lines — matches the
/// streaming/error bubbles.
struct ToolCallCardView: View {
    let title: String
    let summary: String
    let diff: String?
    let tokens: DesignTokens
    var onApprove: (() -> Void)?
    var onDeny: (() -> Void)?
    var onApproveAlways: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.accentSecondary)
                Text(title)
                    .font(AinkradFont.display(12, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Spacer()
            }

            Text(summary)
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .lineLimit(2)

            if let diff, !diff.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(diffAttributed(diff))
                        .font(AinkradFont.mono(11))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }

            if onApprove != nil || onDeny != nil {
                HStack(spacing: 8) {
                    Spacer()
                    ToolCardButton(title: "Deny", tint: tokens.accentTertiary, filled: false, tokens: tokens) { onDeny?() }
                    if let onApproveAlways {
                        ToolCardButton(title: "Allow always", tint: tokens.accentSecondary, filled: false, tokens: tokens) { onApproveAlways() }
                    }
                    ToolCardButton(title: "Approve", tint: tokens.accentPrimary, filled: true, tokens: tokens) { onApprove?() }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
        .shadow(color: tokens.accentSecondary.opacity(0.14), radius: 7)
    }

    private func diffAttributed(_ diff: String) -> AttributedString {
        var out = AttributedString()
        for (i, line) in diff.components(separatedBy: "\n").enumerated() {
            var seg = AttributedString((i == 0 ? "" : "\n") + line)
            if line.hasPrefix("+") { seg.foregroundColor = tokens.accentSecondary }
            else if line.hasPrefix("-") { seg.foregroundColor = tokens.accentTertiary }
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
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
