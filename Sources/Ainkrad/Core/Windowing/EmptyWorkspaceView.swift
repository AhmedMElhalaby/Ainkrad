import SwiftUI
import AinkradAppKit

/// The empty workspace: the ambient sky shows through, with the floating
/// island artwork, wordmark, and a HUD-style Launcher prompt at center.
/// See Navigation & Settings Architecture.md.
struct EmptyWorkspaceView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Whether this workspace is the one currently on screen. Non-active
    /// workspaces (e.g. rendered off-canvas or behind an overlay) still
    /// exist in the view tree, so the island's motion must be gated off
    /// them to avoid burning cycles on artwork nobody sees.
    var isActiveWorkspace: Bool = true

    /// True when a full-screen overlay is covering the island — the
    /// Launcher, Workspace Overview, Settings, App Store, or the quit
    /// confirmation. Motion pauses under any of these too.
    private var overlayPresented: Bool {
        environment.isLauncherPresented
            || environment.isWorkspaceOverviewPresented
            || environment.isSettingsPresented
            || environment.isAppStorePresented
            || environment.quitCoordinator.isConfirming
    }

    private var islandVisible: Bool {
        isActiveWorkspace && !overlayPresented
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(spacing: 0) {
            // The artwork carries the wordmark and tagline itself — no
            // native text over it.
            FloatingIslandView(isVisible: islandVisible)
                .frame(maxWidth: 860, maxHeight: 574)

            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                shortcutHint(keys: ["⌘", "K"], label: "to open an app", tokens: tokens)
                shortcutHint(keys: ["⌥", "⇥"], label: "to manage workspaces", tokens: tokens)
            }
            .padding(.horizontal, AinkradSpacing.lg)
            .padding(.vertical, AinkradSpacing.md)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.28)))
            .overlay(ChamferShape(cut: AinkradRadius.sm).strokeBorder(tokens.accentPrimary.opacity(0.18), lineWidth: 1))
            .padding(.top, 18)
        }
    }

    private func shortcutHint(keys: [String], label: String, tokens: DesignTokens) -> some View {
        HStack(spacing: 7) {
            ForEach(keys, id: \.self) { key in
                AinkradKbd(key)
            }
            Text(label)
                .font(AinkradFont.display(12))
                .kerning(0.5)
                .foregroundStyle(tokens.foreground.opacity(0.45))
                .padding(.leading, 3)
        }
    }
}
