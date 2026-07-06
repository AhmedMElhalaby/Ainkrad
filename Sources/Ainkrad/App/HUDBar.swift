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
    @State private var statusMonitor = SystemStatusMonitor()

    /// The system traffic lights vacate the leading region in full-screen —
    /// show the status bar there instead, gated by the Settings toggle
    /// (AIN-109). `false` in windowed mode, where this region stays exactly
    /// as it was.
    private var showsStatusBar: Bool {
        environment.isFullScreen && environment.generalSettingsStore.showFullScreenStatusBar
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        HStack(spacing: 0) {
            if showsStatusBar {
                FullScreenStatusBarView(monitor: statusMonitor, tokens: tokens)
            }

            // Left side otherwise empty — the system traffic lights occupy
            // this region of the fused title bar in windowed mode.
            Spacer()

            workspaceDots(tokens: tokens)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        // Only run the monitor's timer/NWPathMonitor while the bar is
        // actually shown, so full-screen + the toggle both gate the cost —
        // `initial: true` also starts it if the bar is already visible when
        // `HUDBar` first appears.
        .onChange(of: showsStatusBar, initial: true) { _, isVisible in
            if isVisible {
                statusMonitor.start()
            } else {
                statusMonitor.stop()
            }
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
