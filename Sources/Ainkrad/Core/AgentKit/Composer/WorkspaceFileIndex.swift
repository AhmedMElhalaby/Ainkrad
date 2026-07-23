// Sources/Ainkrad/Core/AgentKit/Composer/WorkspaceFileIndex.swift
import Foundation

struct FileMatch: Equatable, Sendable {
    let path: String
    let name: String
    let score: Int
}

@MainActor
final class WorkspaceFileIndex {
    private let root: URL
    private let fm: FileManager
    private let maxFiles: Int
    private var paths: [String] = []
    private static let skip: Set<String> = [".git", "node_modules", ".build", "DerivedData", ".swiftpm"]

    init(root: URL, fileManager: FileManager = .default, maxFiles: Int = 20_000) {
        self.root = root; self.fm = fileManager; self.maxFiles = maxFiles
    }

    func refresh() {
        var out: [String] = []
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { paths = []; return }
        for case let url as URL in en {
            if Self.skip.contains(url.lastPathComponent) { en.skipDescendants(); continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir { out.append(url.path); if out.count >= maxFiles { break } }
        }
        paths = out
    }

    func search(_ query: String, limit: Int = 12) -> [FileMatch] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        return paths.compactMap { path -> FileMatch? in
            let name = (path as NSString).lastPathComponent
            guard let score = Self.fuzzyScore(query: q, target: path.lowercased(), basename: name.lowercased()) else { return nil }
            return FileMatch(path: path, name: name, score: score)
        }
        .sorted { $0.score > $1.score }
        .prefix(limit).map { $0 }
    }

    /// Subsequence match; +bonus for contiguous runs and basename hits.
    private static func fuzzyScore(query: String, target: String, basename: String) -> Int? {
        var qi = query.startIndex, score = 0, streak = 0
        for ch in target {
            guard qi < query.endIndex else { break }
            if ch == query[qi] { streak += 1; score += 1 + streak; qi = query.index(after: qi) }
            else { streak = 0 }
        }
        guard qi == query.endIndex else { return nil }
        if basename.contains(query) { score += 10 }
        return score
    }
}
