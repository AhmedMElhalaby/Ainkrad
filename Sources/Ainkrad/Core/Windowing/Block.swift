import Foundation

/// One open Built-in App instance living in a tile. See
/// Window & Tile Management Architecture.md. Multiple simultaneous Blocks
/// of the same `appID` are allowed — each is fully independent.
final class Block: Identifiable, Equatable {
    let id: UUID
    let appID: String

    init(id: UUID = UUID(), appID: String) {
        self.id = id
        self.appID = appID
    }

    static func == (lhs: Block, rhs: Block) -> Bool {
        lhs.id == rhs.id
    }
}
