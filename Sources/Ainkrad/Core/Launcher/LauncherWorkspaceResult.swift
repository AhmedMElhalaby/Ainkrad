/// A single row in the Launcher's Workspaces section — see
/// Navigation & Settings Architecture.md.
enum LauncherWorkspaceResult: Identifiable {
    case workspace(Workspace, label: String, isCurrent: Bool)
    case newWorkspace

    var id: String {
        switch self {
        case .workspace(let workspace, _, _): return workspace.id.uuidString
        case .newWorkspace: return "new-workspace"
        }
    }

    var isNewWorkspace: Bool {
        switch self {
        case .newWorkspace: return true
        case .workspace: return false
        }
    }
}
