import Foundation
import AinkradHostRuntime

/// What survives a relaunch: which directories were open in which tabs, which
/// was active, and the view preferences. Paths are stored as strings rather
/// than `URL`s so the document stays legible on disk and version-tolerant.
struct FilesPaneDocument: PersistableDocument {
    static let documentID = "files-pane"

    var tabPaths: [String]
    var activeTabIndex: Int
    var showHidden: Bool
    var sortKey: String
    var sortAscending: Bool
}
