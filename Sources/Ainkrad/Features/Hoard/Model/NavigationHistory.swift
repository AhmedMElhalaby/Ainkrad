import Foundation

/// Browser-style back/forward stack for one tab. A value type, so a tab's
/// history is copied and compared like any other state — and so this is
/// testable without a store, a view, or a filesystem.
struct NavigationHistory: Equatable, Sendable {
    private(set) var entries: [URL]
    private(set) var index: Int

    init(root: URL) {
        self.entries = [Self.canonical(root)]
        self.index = 0
    }

    /// Directory URLs reach us from three sources that disagree on trailing
    /// slashes: `appendingPathComponent` yields none,
    /// `deletingLastPathComponent` yields one, and a user-typed path may have
    /// either. `URL` equality is textual, so `/Users/test/` != `/Users/test`
    /// and Back, sidebar highlighting and breadcrumb matching would all
    /// silently misbehave. Round-tripping through `path` strips the slash and
    /// resolves `.`/`..`, so every URL held here is comparable.
    static func canonical(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path)
    }

    var current: URL { entries[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < entries.count - 1 }

    /// Navigates to `url`. Visiting the directory you are already in is a
    /// no-op rather than a duplicate entry — otherwise a refresh would push
    /// junk onto the stack and Back would appear broken.
    mutating func visit(_ url: URL) {
        let target = Self.canonical(url)
        guard target != current else { return }
        // Anything ahead of the cursor is a branch we just abandoned.
        entries.removeSubrange((index + 1)...)
        entries.append(target)
        index = entries.count - 1
    }

    mutating func goBack() {
        guard canGoBack else { return }
        index -= 1
    }

    mutating func goForward() {
        guard canGoForward else { return }
        index += 1
    }
}
