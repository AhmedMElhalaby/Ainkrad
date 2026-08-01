import Foundation
import Observation
import AinkradHostRuntime

/// Files-specific display settings that have no home in `AppAppearanceStore`
/// (which owns opacity, blur and font overrides for every app).
struct FilesSettingsDocument: PersistableDocument {
    static let documentID = "files-settings"

    /// Row icon size in points. The surrounding row scales with it, so this is
    /// effectively the list's density control.
    var iconSize: Double = 13
    /// Show the size and modified columns. Off gives a name-only list.
    var showMetadataColumns: Bool = true

    init(iconSize: Double = 13, showMetadataColumns: Bool = true) {
        self.iconSize = iconSize
        self.showMetadataColumns = showMetadataColumns
    }
}

@MainActor
@Observable
final class FilesSettingsStore {
    private var document: FilesSettingsDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(FilesSettingsDocument.self) ?? FilesSettingsDocument()
    }

    /// Clamped: a zero-point icon makes rows collapse to a text sliver, and an
    /// oversized one breaks the row's vertical rhythm against the sidebar.
    var iconSize: Double {
        get { document.iconSize }
        set {
            document.iconSize = min(max(10, newValue), 22)
            persistence.save(document)
        }
    }

    var showMetadataColumns: Bool {
        get { document.showMetadataColumns }
        set {
            document.showMetadataColumns = newValue
            persistence.save(document)
        }
    }

    /// Row vertical padding derived from icon size, so density scales as one
    /// coherent thing instead of leaving big icons in cramped rows.
    var rowVerticalPadding: CGFloat { CGFloat(document.iconSize) * 0.38 }
}
