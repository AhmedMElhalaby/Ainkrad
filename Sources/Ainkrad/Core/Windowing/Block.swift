import Foundation
import Observation

/// One open panel: a running Built-in App instance living in a pane.
/// Multiple simultaneous panels of the same `appID` are allowed — each is
/// fully independent. `title` is the user's rename; nil falls back to the
/// app's display name.
@Observable
final class Block: Identifiable, Equatable {
    let id: UUID
    let appID: String
    var title: String?

    init(id: UUID = UUID(), appID: String, title: String? = nil) {
        self.id = id
        self.appID = appID
        self.title = title
    }

    static func == (lhs: Block, rhs: Block) -> Bool {
        lhs.id == rhs.id
    }
}
