import SwiftUI

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
    /// The keyboard remains the fast path; this is the discoverable one.
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

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Open", action: targeting { actions.open(entry) })
            Button("Rename…", action: targeting { actions.rename(entry) })

            Divider()

            Button("Copy", action: targeting(actions.copy))
            Button("Cut", action: targeting(actions.cut))
            Button("Paste", action: actions.paste)

            Divider()

            Button("Compress", action: targeting(actions.compress))
            if actions.canExtract(entry) {
                Button("Extract", action: targeting(actions.extractArchives))
            }

            if entry.isDirectory {
                Divider()
                Button(actions.isPinned(entry) ? "Remove from Favourites" : "Add to Favourites") {
                    actions.togglePin(entry)
                }
            }

            Divider()

            // Destructive role, so the system styles it as the dangerous one.
            // It routes to the Trash like every other delete here — nothing in
            // this app deletes permanently.
            Button("Move to Trash", role: .destructive, action: targeting(actions.trash))
        }
    }
}
