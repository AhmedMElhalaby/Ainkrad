import SwiftUI

/// The single window's content: the active workspace's tile layout, with
/// the Launcher overlaid on top when summoned. See
/// Navigation & Settings Architecture.md.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ZStack {
            AmbientSkyView()

            // Extends under the (hidden) title bar so the HUD is the top of
            // the screen itself — the traffic lights float inside it.
            VStack(spacing: 0) {
                HUDBar()
                TileLayoutView(
                    tileLayout: environment.workspaceManager.activeWorkspace.tileLayout,
                    registry: environment.registry
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(edges: .top)
            // The workspace recedes while the Launcher is summoned.
            .blur(radius: environment.isLauncherPresented ? 14 : 0)
            .animation(.easeOut(duration: 0.18), value: environment.isLauncherPresented)

            if environment.isLauncherPresented {
                LauncherView(store: environment.launcherStore) {
                    environment.isLauncherPresented = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: environment.isLauncherPresented)
        .background(KeyboardShortcutMonitor(environment: environment))
    }
}
