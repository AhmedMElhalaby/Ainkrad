import Foundation
import Observation
import AinkradHostRuntime

/// Files-specific display settings that have no home in `AppAppearanceStore`
/// (which owns opacity, blur and font overrides for every app).
struct FilesSettingsDocument: PersistableDocument {
    static let documentID = "files-settings"

    var iconSize: Double = 13
    var showMetadataColumns: Bool = true

    init(iconSize: Double = 13, showMetadataColumns: Bool = true) {
        self.iconSize = iconSize
        self.showMetadataColumns = showMetadataColumns
    }
}

@MainActor
@Observable
final class FilesSettingsStore {
    /// DIRECTLY STORED, deliberately.
    ///
    /// These were computed properties wrapping a private `document` struct,
    /// and the icon-size slider then had no visible effect: SwiftUI's
    /// observation is reliable for stored properties, and routing reads and
    /// writes through a computed accessor over nested struct state is exactly
    /// where dependency registration gets missed. Persistence happens in
    /// `didSet`, so the storage stays the source of truth for the view and the
    /// document is only ever a serialization detail.
    var iconSize: Double = 13 {
        didSet {
            // Clamped: a zero-point icon collapses rows to a text sliver, and
            // an oversized one breaks the row rhythm against the sidebar.
            let clamped = min(max(10, iconSize), 22)
            if clamped != iconSize {
                iconSize = clamped
                return  // The re-entrant set below persists.
            }
            persist()
        }
    }

    var showMetadataColumns: Bool = true {
        didSet { persist() }
    }

    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let document = persistence.load(FilesSettingsDocument.self) ?? FilesSettingsDocument()
        // Assigned before `persistence` participates in any didSet write-back
        // of values we just read — these are the loaded values, not changes.
        self.iconSize = min(max(10, document.iconSize), 22)
        self.showMetadataColumns = document.showMetadataColumns
    }

    private func persist() {
        persistence.save(FilesSettingsDocument(
            iconSize: iconSize, showMetadataColumns: showMetadataColumns))
    }

    /// Row vertical padding derived from icon size, so density scales as one
    /// coherent thing instead of leaving big icons in cramped rows.
    var rowVerticalPadding: CGFloat { CGFloat(iconSize) * 0.38 }
}
