import Observation

/// Backs the ⌘K Launcher overlay: fuzzy-filtered enabled apps and the
/// open-app action. Workspace management deliberately does NOT live here —
/// it has its own surface and shortcut (see ADR-0008's implementation
/// note). The overlay UI is a separate rendering layer on this store.
@MainActor
@Observable
final class LauncherStore {
    var query: String = ""

    private let registry: BuiltInAppRegistry
    private let workspaceManager: WorkspaceManager

    init(registry: BuiltInAppRegistry, workspaceManager: WorkspaceManager) {
        self.registry = registry
        self.workspaceManager = workspaceManager
    }

    var appResults: [RegisteredApp] {
        registry.enabledApps.filter { fuzzyMatches(query: query, target: $0.displayName) }
    }

    /// The main workspace is the home island and stays empty: summoning an
    /// app from it spawns a fresh workspace (and switches to it). On any
    /// other workspace the app splits into the current layout.
    func selectApp(_ app: RegisteredApp) {
        if workspaceManager.activeWorkspace.isMain {
            workspaceManager.createWorkspace().tileLayout.openApp(app.id)
        } else {
            workspaceManager.activeWorkspace.tileLayout.openApp(app.id)
        }
    }
}
