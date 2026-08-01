import Foundation

/// Browser-style back/forward stack for one tab. A value type, so a tab's
/// history is copied and compared like any other state — and so this is
/// testable without a store, a view, or a filesystem.
struct NavigationHistory: Equatable, Sendable {
    private(set) var entries: [URL]
    private(set) var index: Int

    init(root: URL) {
        self.entries = [root]
        self.index = 0
    }

    var current: URL { entries[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < entries.count - 1 }

    /// Navigates to `url`. Visiting the directory you are already in is a
    /// no-op rather than a duplicate entry — otherwise a refresh would push
    /// junk onto the stack and Back would appear broken.
    mutating func visit(_ url: URL) {
        guard url != current else { return }
        // Anything ahead of the cursor is a branch we just abandoned.
        entries.removeSubrange((index + 1)...)
        entries.append(url)
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
