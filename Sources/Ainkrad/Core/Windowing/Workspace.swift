import Foundation
import Observation

/// One workspace: an identity, a user-editable name, and its own
/// independent tile layout. Exactly one workspace is the **main** one —
/// the home island: it stays empty, and opening an app from it spawns a
/// new workspace instead (see LauncherStore). It can never be deleted.
@Observable
final class Workspace: Identifiable {
    let id: UUID
    let isMain: Bool
    var name: String
    let tileLayout: TileLayout

    init(id: UUID = UUID(), name: String, isMain: Bool = false) {
        self.id = id
        self.name = name
        self.isMain = isMain
        self.tileLayout = TileLayout()
    }
}
