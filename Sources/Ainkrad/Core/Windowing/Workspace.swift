import Foundation

/// One workspace: an identity plus its own independent tile layout.
final class Workspace: Identifiable {
    let id: UUID
    let tileLayout: TileLayout

    init(id: UUID = UUID()) {
        self.id = id
        self.tileLayout = TileLayout()
    }
}
