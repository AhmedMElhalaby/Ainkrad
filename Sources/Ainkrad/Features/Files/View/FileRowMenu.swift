import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// What a row's context menu can do.
///
/// A struct of closures rather than passing `FilesActions` down into the list:
/// the list stays testable and ignorant of the engine, which is the same reason
/// `gitStatus` and `isCut` arrive as closures.
struct FileRowMenuActions {
    var open: (FileEntry) -> Void
    var rename: (FileEntry) -> Void
    var copy: () -> Void
    var cut: () -> Void
    var paste: () -> Void
    var compress: () -> Void
    var extractArchives: () -> Void
    var trash: () -> Void
    var togglePin: (FileEntry) -> Void
    var canExtract: (FileEntry) -> Bool
    var isPinned: (FileEntry) -> Bool
}

extension View {
    /// The right-click menu for one row.
    ///
    /// Until this existed, **every** operation in Files was keyboard-only —
    /// rename was F2 and nothing else, which on a Mac laptop means Fn+F2, so
    /// the single most ordinary thing you do to a file was effectively hidden.
    /// The keyboard remains the fast path; this is the discoverable one, and
    /// every row names its chord so the menu teaches the keyboard rather than
    /// replacing it.
    func fileRowMenu(entry: FileEntry, tab: FilesTab,
                     actions: FileRowMenuActions) -> some View {
        modifier(FileRowMenu(entry: entry, tab: tab, actions: actions))
    }
}

private struct FileRowMenu: ViewModifier {
    let entry: FileEntry
    let tab: FilesTab
    let actions: FileRowMenuActions

    /// Right-clicking a row that is NOT part of the current selection retargets
    /// onto it — the standard behaviour everywhere, and the alternative is a
    /// menu that appears over one file and acts on three others.
    private func targeting(_ action: @escaping () -> Void) -> () -> Void {
        {
            tab.targetContextMenu(at: entry)
            action()
        }
    }

    /// SwiftUI's `.contextMenu`, NOT the kit's `.ainkradContextMenu`.
    ///
    /// The kit's version is the styled one and is where this belongs — but its
    /// right-click catcher is an `NSView` installed in the row's BACKGROUND,
    /// and on these rows it never receives the event: right-click stopped
    /// working entirely when it was used here. Until that is fixed in the kit,
    /// a working system menu beats a beautiful one that does nothing. The
    /// chords still ride in each title, so the menu teaches the keyboard.
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Open  ·  \u{21A9}", action: targeting { actions.open(entry) })
            Button("Rename  ·  \u{2318}R", action: targeting { actions.rename(entry) })

            Divider()

            Button("Copy  ·  \u{2318}C", action: targeting(actions.copy))
            Button("Cut  ·  \u{2318}X", action: targeting(actions.cut))
            Button("Paste  ·  \u{2318}V", action: actions.paste)

            Divider()

            Button("Compress  ·  \u{2325}A", action: targeting(actions.compress))
            if actions.canExtract(entry) {
                Button("Extract  ·  \u{2325}E", action: targeting(actions.extractArchives))
            }

            if entry.isDirectory {
                Divider()
                // NO shortcut shown: \u{2318}D pins the folder you are INSIDE,
                // which is a different target from the one you right-clicked.
                Button(actions.isPinned(entry) ? "Remove from Favourites"
                                               : "Add to Favourites") {
                    actions.togglePin(entry)
                }
            }

            Divider()

            Button("Move to Trash  ·  \u{2318}\u{232B}", role: .destructive,
                   action: targeting(actions.trash))
        }
    }
}
