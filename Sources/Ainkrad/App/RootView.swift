import SwiftUI

/// The single window's content: every workspace's tile layout stays
/// mounted (hidden when inactive) so running sessions survive switching;
/// the Launcher and Workspace Overview overlay on top when summoned.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    private var isOverlayPresented: Bool {
        environment.isLauncherPresented || environment.isWorkspaceOverviewPresented
    }

    var body: some View {
        ZStack {
            // Sky and workspace blur TOGETHER while an overlay is up —
            // blurring only the workspace would rasterize it separately
            // from the sky and visibly seam the composition.
            ZStack {
                AmbientSkyView()

                // Extends under the (hidden) title bar so the HUD is the
                // top of the screen itself — the traffic lights float
                // inside it.
                VStack(spacing: 0) {
                    HUDBar()

                    // ALL workspaces stay in the hierarchy — switching
                    // only toggles visibility, so PTY-backed sessions in
                    // background workspaces keep running.
                    ZStack {
                        ForEach(environment.workspaceManager.workspaces) { workspace in
                            let isActive = workspace.id == environment.workspaceManager.activeWorkspaceID
                            TileLayoutView(
                                workspace: workspace,
                                registry: environment.registry
                            )
                            .opacity(isActive ? 1 : 0)
                            .allowsHitTesting(isActive)
                            .accessibilityHidden(!isActive)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(edges: .top)
            }
            .blur(radius: isOverlayPresented ? 14 : 0)

            if environment.isLauncherPresented {
                LauncherView(store: environment.launcherStore) {
                    environment.isLauncherPresented = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if environment.isWorkspaceOverviewPresented {
                WorkspaceOverviewView {
                    environment.isWorkspaceOverviewPresented = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: isOverlayPresented)
        .background(KeyboardShortcutMonitor(environment: environment))
    }
}
