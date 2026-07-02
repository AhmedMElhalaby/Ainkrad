import SwiftUI

/// The single window's content: the active workspace's tile layout, with
/// the Launcher overlaid on top when summoned. See
/// Navigation & Settings Architecture.md.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ZStack {
            AmbientSkyView()

            VStack(spacing: 0) {
                HUDBar()
                TileLayoutView(
                    tileLayout: environment.workspaceManager.activeWorkspace.tileLayout,
                    registry: environment.registry
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if environment.isLauncherPresented {
                LauncherView(store: environment.launcherStore) {
                    environment.isLauncherPresented = false
                }
            }
        }
        .background(KeyboardShortcutMonitor(environment: environment))
    }
}
