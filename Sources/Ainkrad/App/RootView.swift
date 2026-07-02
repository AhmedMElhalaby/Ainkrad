import SwiftUI

/// The single window's content: the active workspace's tile layout, with
/// the Launcher overlaid on top when summoned. See
/// Navigation & Settings Architecture.md.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ZStack {
            environment.themeManager.tokens.background.ignoresSafeArea()
            TileLayoutView(
                tileLayout: environment.workspaceManager.activeWorkspace.tileLayout,
                registry: environment.registry
            )

            if environment.isLauncherPresented {
                LauncherView(store: environment.launcherStore) {
                    environment.isLauncherPresented = false
                }
            }
        }
        .background(KeyboardShortcutMonitor(environment: environment))
    }
}
