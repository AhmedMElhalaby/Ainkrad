import Foundation
import Observation

/// How a tab presents its layout: the full split tree, or Focus Mode —
/// one panel large with the rest in a compact side strip. Switching modes
/// never touches the layout tree.
enum TabViewMode: String, Codable {
    case split
    case focus
}

/// One tab inside a workspace: a name, one layout tree, and a view mode.
@Observable
final class WorkspaceTab: Identifiable {
    let id: UUID
    var name: String
    var viewMode: TabViewMode
    let tileLayout: TileLayout

    init(id: UUID = UUID(), name: String, viewMode: TabViewMode = .split) {
        self.id = id
        self.name = name
        self.viewMode = viewMode
        self.tileLayout = TileLayout()
    }
}
