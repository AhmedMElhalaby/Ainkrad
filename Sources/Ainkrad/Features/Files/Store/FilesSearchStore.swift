import Foundation
import Observation

/// Which finder affordance is open, if any.
enum FilesFinderMode: Equatable {
    /// ⌘F / the always-present field — recursive search below the current
    /// directory, running as you type.
    case search
    /// ⌘P — fuzzy jump across the tree, ranked.
    case jump
}

/// Drives the always-present filter field and the recursive search / jump.
///
/// Everything runs AS YOU TYPE. The first cut required Return to start a
/// search and then blocked until the whole tree had been walked, which is the
/// slow, unresponsive behaviour that made it feel broken. Now:
///
/// - the in-folder filter is pure and instant, per keystroke;
/// - the recursive search is debounced, cancellable, and streams results in as
///   they are found rather than after the walk completes;
/// - the jump palette shows its first results immediately instead of waiting
///   for a full 5,000-entry traversal.
@MainActor
@Observable
final class FilesSearchStore {
    private let fileSystem: any FileSystemServing

    /// The always-visible in-folder filter. Separate from `queryText` so
    /// opening the palette does not clear what you had filtered.
    var filterText = ""

    private(set) var mode: FilesFinderMode?
    var queryText = "" {
        didSet { if queryText != oldValue { scheduleSearch() } }
    }
    private(set) var results: [SearchHit] = []
    private(set) var isSearching = false
    private(set) var didTruncate = false

    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var searchRoot: URL?

    /// Long enough to coalesce fast typing, short enough to feel live.
    private static let debounce = Duration.milliseconds(140)

    init(fileSystem: any FileSystemServing) {
        self.fileSystem = fileSystem
    }

    var isActive: Bool { mode != nil }
    var isFiltering: Bool { !filterText.isEmpty }

    func open(_ mode: FilesFinderMode, root: URL) {
        self.mode = mode
        self.searchRoot = root
        queryText = ""
        results = []
        didTruncate = false
        if mode == .jump { startJump(root: root) }
    }

    func close() {
        cancelWork()
        mode = nil
        queryText = ""
        results = []
        isSearching = false
    }

    func clearFilter() { filterText = "" }

    private func cancelWork() {
        debounceTask?.cancel()
        searchTask?.cancel()
        debounceTask = nil
        searchTask = nil
    }

    // MARK: - In-folder filter (pure, instant)

    /// Filters entries already in memory. Safe on every keystroke — no disk
    /// access, no task, no debounce.
    func filtered(_ entries: [FileEntry]) -> [FileEntry] {
        guard !filterText.isEmpty else { return entries }
        return fuzzyRank(entries, pattern: filterText) { $0.name }.map(\.item)
    }

    // MARK: - Recursive search (debounced, streaming)

    private func scheduleSearch() {
        guard mode == .search, let root = searchRoot else { return }
        cancelWork()
        guard !queryText.isEmpty else {
            results = []
            isSearching = false
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.runSearch(root: root)
        }
    }

    private func runSearch(root: URL) {
        let query = SearchQuery(text: queryText)
        results = []
        didTruncate = false
        isSearching = true

        let stream = Self.stream(root: root, query: query, fileSystem: fileSystem)
        searchTask = Task { [weak self] in
            for await batch in stream {
                guard !Task.isCancelled else { return }
                self?.results.append(contentsOf: batch)
            }
            guard !Task.isCancelled else { return }
            self?.isSearching = false
            self?.didTruncate = (self?.results.count ?? 0) >= query.limit
        }
    }

    // MARK: - Jump palette

    private func startJump(root: URL) {
        cancelWork()
        results = []
        isSearching = true
        var query = SearchQuery(text: "")
        query.matchAll = true
        // A tighter cap than the old 5,000: the palette ranks in memory and
        // shows 60, so gathering thousands more only delayed the first paint.
        query.limit = 1_500
        query.maxDepth = 8

        let stream = Self.stream(root: root, query: query, fileSystem: fileSystem)
        searchTask = Task { [weak self] in
            // Candidates stream in, so the palette is usable from the first
            // directory rather than after the whole walk.
            for await batch in stream {
                guard !Task.isCancelled else { return }
                self?.results.append(contentsOf: batch)
            }
            self?.isSearching = false
        }
    }

    /// Builds the batch stream OFF the main actor.
    ///
    /// `nonisolated` deliberately: `AsyncStream`'s builder is a `sending`
    /// closure, and constructing it inside main-actor-isolated code makes the
    /// compiler (correctly) call it a data race.
    private nonisolated static func stream(root: URL, query: SearchQuery,
                                           fileSystem: any FileSystemServing)
        -> AsyncStream<[SearchHit]> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                _ = searchFiles(root: root, query: query, fileSystem: fileSystem,
                                isCancelled: { Task.isCancelled },
                                onBatch: { continuation.yield($0) })
                continuation.finish()
            }
        }
    }

    /// Ranked view for the palette.
    var rankedResults: [SearchHit] {
        guard mode == .jump, !queryText.isEmpty else { return Array(results.prefix(60)) }
        return fuzzyRank(results, pattern: queryText) { $0.entry.name }
            .prefix(60).map(\.item)
    }
}
