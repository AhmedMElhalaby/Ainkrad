import SwiftUI

/// The top edge of the screen — not a bar. The system traffic lights and
/// the clickable workspace dots float directly on the sky, with no
/// background tint and no separator, so the title-bar region is seamlessly
/// part of the workspace.
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
                    Group {
                        if workspace.isMain {
                            // The home island wears the chevron mark.
                            ChevronMark()
                                .fill(isActive ? tokens.accentSecondary : tokens.foreground.opacity(0.35))
                                .frame(width: isActive ? 10 : 8, height: isActive ? 8.5 : 7)
                        } else {
                            Rectangle()
                                .fill(isActive ? tokens.accentSecondary : tokens.foreground.opacity(0.28))
                                .frame(width: isActive ? 7 : 5, height: isActive ? 7 : 5)
                                .rotationEffect(.degrees(45))
                        }
                    }
                    .shadow(color: isActive ? tokens.accentSecondary.opacity(0.9) : .clear, radius: 4)
                    .frame(width: 12, height: 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(workspace.name)\(index < 9 ? " — ⌘\(index + 1)" : "")")
            }
        }
        .animation(.easeOut(duration: 0.18), value: manager.activeWorkspaceID)
    }
}
