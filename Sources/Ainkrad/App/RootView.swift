import SwiftUI

/// The single window's content: every workspace — and every tab within it
/// — stays mounted (hidden when inactive) so running sessions survive
/// switching; the Launcher and Workspace Overview overlay on top when
/// summoned.
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

                    ForEach(environment.workspaceManager.workspaces) { workspace in
                        let isActiveWorkspace = workspace.id == environment.workspaceManager.activeWorkspaceID

                        VStack(spacing: 0) {
                            if !workspace.isMain, isActiveWorkspace {
                                TabStripView(workspace: workspace)
                            }

                            ZStack {
                                ForEach(workspace.tabs) { tab in
                                    let isActiveTab = tab.id == workspace.selectedTabID
                                    TabContentView(tab: tab, registry: environment.registry)
                                        .opacity(isActiveTab ? 1 : 0)
                                        .allowsHitTesting(isActiveTab)
                                        .accessibilityHidden(!isActiveTab)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .opacity(isActiveWorkspace ? 1 : 0)
                        .allowsHitTesting(isActiveWorkspace)
                        .accessibilityHidden(!isActiveWorkspace)
                        .frame(maxWidth: .infinity, maxHeight: isActiveWorkspace ? .infinity : 0)
                    }
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
