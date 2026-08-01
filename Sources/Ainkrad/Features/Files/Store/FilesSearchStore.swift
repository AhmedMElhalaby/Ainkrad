import Foundation
import Observation

/// Which finder affordance is open, if any.
enum FilesFinderMode: Equatable {
    /// `/` — filters the CURRENT directory as you type. Instant, no walk.
    case filter
    /// ⌘F — recursive search from the current directory. Walks, so it runs off
    /// the main actor and is cancellable.
    case search
    /// ⌘P — fuzzy jump across the tree, ranked.
    case jump
}

/// Drives the filter / search / jump affordances.
///
/// Filter and jump are pure functions over data already in memory, so they
/// update per keystroke. Search walks the disk, so it is debounced, cancellable
/// and explicitly not run on every character.
@MainActor
@Observable
final class FilesSearchStore {
    private let fileSystem: any FileSystemServing

    private(set) var mode: FilesFinderMode?
    var queryText = ""
    private(set) var results: [SearchHit] = []
    private(set) var isSearching = false
    private(set) var didTruncate = false

    private var searchTask: Task<Void, Never>?

    init(fileSystem: any FileSystemServing) {
        self.fileSystem = fileSystem
    }

    var isActive: Bool { mode != nil }

    func open(_ mode: FilesFinderMode) {
        self.mode = mode
        queryText = ""
        results = []
        didTruncate = false
    }

    func close() {
        searchTask?.cancel()
        searchTask = nil
        mode = nil
        queryText = ""
        results = []
        isSearching = false
    }

    /// Filters the entries already loaded — no disk access, safe per keystroke.
    func filtered(_ entries: [FileEntry]) -> [FileEntry] {
        guard mode == .filter, !queryText.isEmpty else { return entries }
        return fuzzyRank(entries, pattern: queryText) { $0.name }.map(\.item)
    }

    /// Recursive search. Cancels any in-flight walk first, so typing doesn't
    /// stack up overlapping traversals of the same tree.
    func runSearch(root: URL) {
        searchTask?.cancel()
        let query = SearchQuery(text: queryText)
        guard !query.text.isEmpty else {
            results = []
            return
        }

        isSearching = true
        let fileSystem = self.fileSystem
        searchTask = Task { [weak self] in
            // Off the main actor: a deep tree walk would otherwise freeze the
            // pane it is searching.
            let hits = await Task.detached(priority: .userInitiated) { () -> [SearchHit] in
                searchFiles(root: root, query: query, fileSystem: fileSystem,
                            isCancelled: { Task.isCancelled })
            }.value

            guard !Task.isCancelled else { return }
            self?.results = hits
            self?.didTruncate = hits.count >= query.limit
            self?.isSearching = false
        }
    }

    /// Fuzzy jump candidates, gathered once when the palette opens and then
    /// ranked in memory per keystroke.
    func loadJumpCandidates(root: URL) {
        searchTask?.cancel()
        isSearching = true
        let fileSystem = self.fileSystem
        searchTask = Task { [weak self] in
            var query = SearchQuery(text: "")
            query.limit = 5_000
            let all = await Task.detached(priority: .userInitiated) { () -> [SearchHit] in
                // An empty query matches nothing in `searchFiles`, so gather by
                // walking with a match-everything pattern instead.
                collectTree(root: root, limit: query.limit, maxDepth: query.maxDepth,
                            fileSystem: fileSystem, isCancelled: { Task.isCancelled })
            }.value
            guard !Task.isCancelled else { return }
            self?.results = all
            self?.isSearching = false
        }
    }

    /// Ranked view of `results` for the jump palette.
    var rankedResults: [SearchHit] {
        guard mode == .jump, !queryText.isEmpty else { return results }
        return fuzzyRank(results, pattern: queryText) { $0.entry.name }.map(\.item).prefix(60).map { $0 }
    }
}

/// Walks the tree collecting every entry, for the jump palette's candidate set.
/// Shares `searchFiles`' pruning rules so it doesn't wander into
/// `node_modules` either.
func collectTree(root: URL, limit: Int, maxDepth: Int,
                 fileSystem: any FileSystemServing,
                 isCancelled: () -> Bool = { false }) -> [SearchHit] {
    var query = SearchQuery(text: "")
    query.limit = limit
    query.maxDepth = maxDepth
    // Explicit match-all: an empty `text` deliberately finds NOTHING for a
    // search, so the palette has to ask for everything rather than rely on
    // empty meaning "all".
    query.matchAll = true
    return searchFiles(root: root, query: query, fileSystem: fileSystem,
                       isCancelled: isCancelled)
}
