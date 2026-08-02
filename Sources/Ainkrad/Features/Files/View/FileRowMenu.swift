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

    /// `AinkradMenuItem` carries no shortcut field, so the chord rides in the
    /// title. Deliberately NOT a fake right-aligned column — without kit
    /// support the spacing would drift per row and read as broken.
    private func item(_ title: String, _ shortcut: String?, _ symbol: String,
                      destructive: Bool = false,
                      action: @escaping () -> Void) -> AinkradMenuItem {
        AinkradMenuItem(title: shortcut.map { "\(title)  ·  \($0)" } ?? title,
                        systemName: symbol, isDestructive: destructive, action: action)
    }

    private var items: [AinkradMenuItem] {
        var items: [AinkradMenuItem] = [
            item("Open", "↩", entry.isDirectory ? "folder" : "arrow.up.forward.app",
                 action: targeting { actions.open(entry) }),
            item("Rename", "⌘R", "character.cursor.ibeam",
                 action: targeting { actions.rename(entry) }),
            item("Copy", "⌘C", "doc.on.doc", action: targeting(actions.copy)),
            item("Cut", "⌘X", "scissors", action: targeting(actions.cut)),
            item("Paste", "⌘V", "doc.on.clipboard", action: actions.paste),
            item("Compress", "⌥A", "archivebox", action: targeting(actions.compress))
        ]

        if actions.canExtract(entry) {
            items.append(item("Extract", "⌥E", "arrow.up.bin",
                              action: targeting(actions.extractArchives)))
        }

        if entry.isDirectory {
            // NO shortcut shown: ⌘D pins the folder you are INSIDE, which is a
            // different target from the folder you right-clicked. Labelling it
            // ⌘D would teach a chord that does something else.
            let pinned = actions.isPinned(entry)
            items.append(item(pinned ? "Remove from Favourites" : "Add to Favourites",
                              nil, pinned ? "star.slash" : "star",
                              action: { actions.togglePin(entry) }))
        }

        // Last and tinted danger — it routes to the Trash like every delete
        // here; nothing in this app deletes permanently.
        items.append(item("Move to Trash", "⌘⌫", "trash", destructive: true,
                          action: targeting(actions.trash)))
        return items
    }

    func body(content: Content) -> some View {
        // The kit's own menu, NOT SwiftUI's `.contextMenu`: that renders a
        // system `NSMenu`, which cannot be styled and would drop a stock macOS
        // panel into a surface that is otherwise entirely Cardinal.
        content.ainkradContextMenu(items)
    }
}
