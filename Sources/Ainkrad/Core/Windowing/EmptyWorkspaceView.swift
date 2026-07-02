import SwiftUI

/// The empty workspace: the ambient sky shows through, with the floating
/// island artwork, wordmark, and a HUD-style Launcher prompt at center.
/// See Navigation & Settings Architecture.md.
struct EmptyWorkspaceView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(spacing: 0) {
            // The artwork carries the wordmark and tagline itself — no
            // native text over it.
            FloatingIslandView()
                .frame(maxWidth: 860, maxHeight: 574)

            HStack(spacing: 7) {
                keycap("⌘", tokens: tokens)
                keycap("K", tokens: tokens)
                Text("to open an app")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                    .padding(.leading, 3)
            }
            .padding(.top, 18)
        }
    }

    private func keycap(_ label: String, tokens: DesignTokens) -> some View {
        Text(label)
            .font(AinkradFont.mono(11, weight: .medium))
            .foregroundStyle(tokens.foreground.opacity(0.8))
            .frame(width: 24, height: 22)
            .background(tokens.surfaceElevated.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(tokens.accentPrimary.opacity(0.35), lineWidth: 1)
            )
    }
}
