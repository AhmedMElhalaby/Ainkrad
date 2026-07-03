import Foundation
import Observation

/// How a workspace presents its layout: the full split tree, or Focus
/// Mode — one panel large with the rest in a compact switcher rail.
/// Switching modes never touches the layout tree.
enum WorkspaceViewMode: String, Codable {
    case split
    case focus
}

/// One workspace: an identity, a user-editable name, a view mode, and its
/// own independent tile layout. Exactly one workspace is the **main** one
/// — the home island: it stays empty, and opening an app from it spawns a
/// new workspace instead (see LauncherStore). It can never be deleted.
@Observable
final class Workspace: Identifiable {
    let id: UUID
    let isMain: Bool
    var name: String
    var viewMode: WorkspaceViewMode
    let tileLayout: TileLayout

    init(id: UUID = UUID(), name: String, isMain: Bool = false, viewMode: WorkspaceViewMode = .split) {
        self.id = id
        self.name = name
        self.isMain = isMain
        self.viewMode = viewMode
        self.tileLayout = TileLayout()
    }
}
