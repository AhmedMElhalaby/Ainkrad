import Foundation
import Observation

/// One tab: a current directory, its listing, the selection within it, and the
/// back/forward history that got there. Owns no views and no `FileManager` —
/// it talks to `FileSystemServing`, so it is fully testable with a fake.
@MainActor
@Observable
final class FilesTab: Identifiable {
    let id = UUID()

    private let fileSystem: any FileSystemServing
    private var history: NavigationHistory

    /// The raw listing, unfiltered and unsorted. `visibleEntries` derives the
    /// display order — keeping both means toggling hidden files or re-sorting
    /// never costs a directory read.
    private(set) var entries: [FileEntry] = []
    /// Human-readable reason the last load failed, or `nil`.
    private(set) var loadError: String?

    var selection: Set<URL> = []
    var sortKey: FileSortKey = .name
    var sortAscending = true
    var showHidden = false

    var currentDirectory: URL { history.current }
    var title: String { currentDirectory.lastPathComponent }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    var visibleEntries: [FileEntry] {
        sortedEntries(filteredEntries(entries, showHidden: showHidden),
                      by: sortKey, ascending: sortAscending)
    }

    /// The keyboard cursor's row in `visibleEntries`. Distinct from
    /// `selection`: you move the cursor to look, and select to act — the
    /// orthodox-manager separation that makes Space-to-select meaningful.
    private(set) var cursorIndex = 0

    var cursorEntry: FileEntry? {
        visibleEntries.indices.contains(cursorIndex) ? visibleEntries[cursorIndex] : nil
    }

    func moveCursor(by delta: Int) {
        let count = visibleEntries.count
        guard count > 0 else { cursorIndex = 0; return }
        cursorIndex = min(max(0, cursorIndex + delta), count - 1)
    }

    func moveCursorToStart() { cursorIndex = 0 }

    func moveCursorToEnd() {
        cursorIndex = max(0, visibleEntries.count - 1)
    }

    /// `extending` is the ⇧-arrow case: add to the selection rather than
    /// replacing it.
    func selectCursor(extending: Bool) {
        guard let entry = cursorEntry else { return }
        if extending {
            selection.insert(entry.url)
        } else {
            selection = [entry.url]
        }
    }

    func selectAll() {
        selection = Set(visibleEntries.map(\.url))
    }

    func invertSelection() {
        let all = Set(visibleEntries.map(\.url))
        selection = all.subtracting(selection)
    }

    /// Enter: descend into a directory. Files do nothing in M1 — opening
    /// them arrives with the preview pane in M3.
    func activateCursor() {
        guard let entry = cursorEntry, entry.isDirectory else { return }
        descend(into: entry)
    }

    init(directory: URL, fileSystem: any FileSystemServing) {
        self.fileSystem = fileSystem
        self.history = NavigationHistory(root: directory)
        reload()
    }

    /// Re-reads the current directory. Called on creation, on navigation, and
    /// by the FSEvents watcher.
    func reload() {
        do {
            entries = try fileSystem.contents(of: currentDirectory)
            loadError = nil
        } catch {
            // Degrade, don't crash: empty the list and say why. The pane
            // renders an error state rather than a blank surface.
            entries = []
            loadError = error.localizedDescription
        }
        // A stale cursor pointing past the end of a smaller listing would make
        // arrow keys appear dead until the user scrolled back into range.
        cursorIndex = min(cursorIndex, max(0, visibleEntries.count - 1))
    }

    /// Navigates to `url` even if it turns out to be unreadable — the failure
    /// then shows up in place, at the path the user asked for, instead of
    /// silently doing nothing and looking broken.
    func navigate(to url: URL) {
        history.visit(url)
        selection.removeAll()
        cursorIndex = 0
        reload()
    }

    func descend(into entry: FileEntry) {
        guard entry.isDirectory else { return }
        navigate(to: entry.url)
    }

    func ascend() {
        let parent = currentDirectory.deletingLastPathComponent()
        guard parent != currentDirectory else { return }
        navigate(to: parent)
    }

    func goBack() {
        guard history.canGoBack else { return }
        history.goBack()
        selection.removeAll()
        cursorIndex = 0
        reload()
    }

    func goForward() {
        guard history.canGoForward else { return }
        history.goForward()
        selection.removeAll()
        cursorIndex = 0
        reload()
    }
}
