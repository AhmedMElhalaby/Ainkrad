import Foundation
import Observation

/// One open Built-in App instance living in a tile. See
/// Window & Tile Management Architecture.md. Multiple simultaneous Blocks
/// of the same `appID` are allowed — each is fully independent.
///
/// `@Observable` for one reason: `title` is user-editable (Focus Mode tabs
/// can be renamed), so the tab strip has to re-render when it changes.
@Observable
final class Block: Identifiable, Equatable {
    let id: UUID
    let appID: String
    /// The user's name for this pane, set by renaming its Focus-Mode tab.
    /// `nil` (and empty, which renaming normalizes to `nil`) means "use the
    /// app's display name" — so a never-renamed pane keeps following the app
    /// rather than freezing a copy of its name.
    var title: String?

    init(id: UUID = UUID(), appID: String, title: String? = nil) {
        self.id = id
        self.appID = appID
        self.title = title
    }

    /// The label to show for this pane: the user's name if it has one, else
    /// the app's display name (passed in — `Block` knows nothing of the registry).
    func displayTitle(appName: String?) -> String {
        if let title, !title.isEmpty { return title }
        return appName ?? appID
    }

    /// Applies a rename, normalizing whitespace-only input back to "no name"
    /// so clearing the field restores the app's own name.
    func rename(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? nil : trimmed
    }

    static func == (lhs: Block, rhs: Block) -> Bool {
        lhs.id == rhs.id
    }
}
