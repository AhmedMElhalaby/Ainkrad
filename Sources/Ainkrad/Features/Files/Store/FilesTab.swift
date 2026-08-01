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
    }

    /// Navigates to `url` even if it turns out to be unreadable — the failure
    /// then shows up in place, at the path the user asked for, instead of
    /// silently doing nothing and looking broken.
    func navigate(to url: URL) {
        history.visit(url)
        selection.removeAll()
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
        reload()
    }

    func goForward() {
        guard history.canGoForward else { return }
        history.goForward()
        selection.removeAll()
        reload()
    }
}
