import SwiftUI

/// The OS status strip along the top of the window: wordmark on the left,
/// workspace readout and clock on the right, separated from the canvas by
/// an accent hairline. Deliberately HUD language — thin, luminous, mono
/// readouts — not window chrome.
///
/// NOTE: the workspace readout intentionally deviates from ADR-0008's
/// "no persistent workspace indicator" — flagged for review as part of the
/// OS-direction visual redesign.
struct HUDBar: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let tokens = environment.themeManager.tokens

        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ChevronMark()
                    .fill(tokens.accentSecondary)
                    .frame(width: 13, height: 11)
                Text("AINKRAD")
                    .font(AinkradFont.display(11, weight: .semibold))
                    .kerning(3.5)
                    .foregroundStyle(tokens.foreground.opacity(0.85))
            }

            Spacer()

            HStack(spacing: 16) {
                workspaceReadout(tokens: tokens)
                clock(tokens: tokens)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(tokens.background.opacity(0.55))
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, tokens.accentPrimary.opacity(0.55), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
    }

    private func workspaceReadout(tokens: DesignTokens) -> some View {
        let manager = environment.workspaceManager
        let position = (manager.workspaces.firstIndex(where: { $0.id == manager.activeWorkspaceID }) ?? 0) + 1

        return Text(String(format: "WS %02d / %02d", position, manager.workspaces.count))
            .font(AinkradFont.mono(10, weight: .medium))
            .kerning(1)
            .foregroundStyle(tokens.accentSecondary.opacity(0.9))
    }

    private func clock(tokens: DesignTokens) -> some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(AinkradFont.mono(10, weight: .medium))
                .kerning(1)
                .foregroundStyle(tokens.foreground.opacity(0.6))
        }
    }
}
