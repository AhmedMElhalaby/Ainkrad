import SwiftUI

/// The empty workspace: the ambient sky shows through, with the floating
/// island artwork and wordmark at center.
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
        // The artwork carries the wordmark and tagline itself — no native
        // text over it.
        FloatingIslandView(isVisible: islandVisible)
            .frame(maxWidth: 860, maxHeight: 574)
    }
}
