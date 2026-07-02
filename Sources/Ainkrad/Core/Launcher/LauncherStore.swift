import Observation

/// Backs the ⌘K App Launcher overlay: fuzzy-filtered Apps and Workspaces
/// sections, and the actions selecting a result performs. See ADR-0008 App
/// Launcher & Workspace Switching and Navigation & Settings Architecture.md.
/// The overlay UI itself (summon/dismiss, keyboard navigation) is a
/// separate rendering layer built on top of this store.
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

    var appResults: [BuiltInApp.Type] {
        registry.enabledApps.filter { fuzzyMatches(query: query, target: $0.displayName) }
    }

    var workspaceResults: [LauncherWorkspaceResult] {
        let activeID = workspaceManager.activeWorkspaceID
        let workspaceRows = workspaceManager.workspaces.enumerated().map { index, workspace in
            LauncherWorkspaceResult.workspace(
                workspace,
                label: "Workspace \(index + 1)",
                isCurrent: workspace.id == activeID
            )
        }
        let rows = workspaceRows + [.newWorkspace]

        return rows.filter { result in
            switch result {
            case .workspace(_, let label, _): return fuzzyMatches(query: query, target: label)
            case .newWorkspace: return fuzzyMatches(query: query, target: "New Workspace")
            }
        }
    }

    func selectApp(_ app: BuiltInApp.Type) {
        workspaceManager.activeWorkspace.tileLayout.openApp(app.id)
    }

    func selectWorkspace(_ workspace: Workspace) {
        workspaceManager.switchTo(workspace.id)
    }

    func selectNewWorkspace() {
        workspaceManager.createWorkspace()
    }
}
