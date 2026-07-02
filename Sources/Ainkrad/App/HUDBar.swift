import SwiftUI

/// The OS status strip fused with the (hidden) title bar at the very top
/// of the screen: the system traffic lights float inside its left side,
/// the clickable workspace dots sit on the right, over an accent hairline.
/// Deliberately HUD language, not window chrome.
///
/// NOTE: the workspace dots intentionally supersede ADR-0008's
/// "no persistent workspace indicator" — approved as part of the
/// OS-direction visual redesign (clickable, brand-diamond styling).
struct HUDBar: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let tokens = environment.themeManager.tokens

        HStack(spacing: 0) {
            // Left side intentionally empty — the system traffic lights
            // occupy this region of the fused title bar.
            Spacer()

            workspaceDots(tokens: tokens)
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

    /// One diamond per workspace — the brand's diamond accent (the mark
    /// inside the chevron), not a generic dot. The active one glows in
    /// accentSecondary; clicking any switches to it.
    private func workspaceDots(tokens: DesignTokens) -> some View {
        let manager = environment.workspaceManager

        return HStack(spacing: 8) {
            ForEach(Array(manager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                let isActive = workspace.id == manager.activeWorkspaceID

                Button {
                    manager.switchTo(workspace.id)
                } label: {
                    Rectangle()
                        .fill(isActive ? tokens.accentSecondary : tokens.foreground.opacity(0.28))
                        .frame(width: isActive ? 7 : 5, height: isActive ? 7 : 5)
                        .rotationEffect(.degrees(45))
                        .shadow(color: isActive ? tokens.accentSecondary.opacity(0.9) : .clear, radius: 4)
                        .frame(width: 11, height: 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Workspace \(index + 1)\(index < 9 ? " — ⌘\(index + 1)" : "")")
            }
        }
        .animation(.easeOut(duration: 0.18), value: manager.activeWorkspaceID)
    }
}
