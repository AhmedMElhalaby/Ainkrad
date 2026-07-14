import SwiftUI

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
                    Button("Deny") { onDeny?() }
                        .buttonStyle(.plain)
                        .foregroundStyle(tokens.accentTertiary)
                    if let onApproveAlways {
                        Button("Allow always") { onApproveAlways() }
                            .buttonStyle(.plain)
                            .foregroundStyle(tokens.accentSecondary)
                    }
                    Button("Approve") { onApprove?() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(tokens.accentPrimary.opacity(0.9)))
                        .foregroundStyle(tokens.background)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentSecondary.opacity(0.3), lineWidth: 1))
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
