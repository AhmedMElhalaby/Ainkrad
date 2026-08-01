import Testing
import Foundation
@testable import Ainkrad

@Suite("File search")
struct FileSearchTests {
    private func makeTree() -> InMemoryFileSystem {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/root"))
        fs.add(directory: "/root", children: ["src/", "docs/", "node_modules/", ".git/", "README.md"])
        fs.add(directory: "/root/src", children: ["main.swift", "helper.swift", "deep/"])
        fs.add(directory: "/root/src/deep", children: ["nested.swift"])
        fs.add(directory: "/root/docs", children: ["guide.md", "readme-extra.md"])
        // Both of these are traps a naive recursive search falls into.
        fs.add(directory: "/root/node_modules", children: ["lodash.js", "react.js"])
        fs.add(directory: "/root/.git", children: ["config"])
        return fs
    }

    private func search(_ text: String, _ mutate: (inout SearchQuery) -> Void = { _ in })
        -> [SearchHit] {
        var query = SearchQuery(text: text)
        mutate(&query)
        return searchFiles(root: URL(fileURLWithPath: "/root"), query: query,
                           fileSystem: makeTree())
    }

    @Test("finds matches recursively")
    func findsRecursively() {
        let names = search("swift").map(\.entry.name).sorted()
        #expect(names == ["helper.swift", "main.swift", "nested.swift"])
    }

    @Test("reports where each hit was found")
    func reportsLocation() {
        let hit = search("nested").first
        #expect(hit?.relativeDirectory == "src/deep")
    }

    @Test("a hit in the root directory reports \".\"")
    func rootRelativePath() {
        #expect(search("README").first?.relativeDirectory == ".")
    }

    // The single biggest reason naive recursive search feels broken.
    @Test("never descends into node_modules, .git or build directories")
    func prunesNoiseDirectories() {
        #expect(search("lodash").isEmpty)
        #expect(search("config").isEmpty)
    }

    @Test("hidden entries are excluded unless asked for")
    func hiddenExcluded() {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/root"))
        fs.add(directory: "/root", children: [".secret-notes", "notes.txt"])

        var query = SearchQuery(text: "notes")
        var hits = searchFiles(root: URL(fileURLWithPath: "/root"), query: query, fileSystem: fs)
        #expect(hits.map(\.entry.name) == ["notes.txt"])

        query.includeHidden = true
        hits = searchFiles(root: URL(fileURLWithPath: "/root"), query: query, fileSystem: fs)
        #expect(hits.count == 2)
    }

    @Test("matching is case-insensitive by default and exact when asked")
    func caseSensitivity() {
        #expect(!search("README").isEmpty)
        #expect(!search("readme").isEmpty)
        #expect(search("readme") { $0.caseSensitive = true }.map(\.entry.name) == ["readme-extra.md"])
    }

    @Test("an empty query finds nothing rather than everything")
    func emptyQuery() {
        #expect(search("").isEmpty)
    }

    // An unbounded search that finds 400,000 matches isn't more useful — it
    // just hangs the pane.
    @Test("results are capped at the limit")
    func respectsLimit() {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/root"))
        fs.add(directory: "/root", children: (0..<50).map { "match\($0).txt" })

        var query = SearchQuery(text: "match")
        query.limit = 10
        let hits = searchFiles(root: URL(fileURLWithPath: "/root"), query: query, fileSystem: fs)
        #expect(hits.count == 10)
    }

    @Test("depth is bounded so a pathological tree cannot run forever")
    func respectsDepth() {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/root"))
        fs.add(directory: "/root", children: ["a/"])
        fs.add(directory: "/root/a", children: ["b/"])
        fs.add(directory: "/root/a/b", children: ["target.txt"])

        var query = SearchQuery(text: "target")
        query.maxDepth = 1
        #expect(searchFiles(root: URL(fileURLWithPath: "/root"), query: query, fileSystem: fs).isEmpty)

        query.maxDepth = 5
        #expect(!searchFiles(root: URL(fileURLWithPath: "/root"), query: query, fileSystem: fs).isEmpty)
    }

    @Test("cancellation stops the walk")
    func cancellation() {
        let hits = searchFiles(root: URL(fileURLWithPath: "/root"),
                               query: SearchQuery(text: "swift"),
                               fileSystem: makeTree(),
                               isCancelled: { true })
        #expect(hits.isEmpty)
    }

    @Test("an unreadable directory is skipped, not fatal")
    func unreadableDirectorySkipped() {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/root"))
        // "locked/" is listed as a child but has no registered contents, so
        // reading it throws — exactly like a permission failure.
        fs.add(directory: "/root", children: ["locked/", "found.txt"])
        let hits = searchFiles(root: URL(fileURLWithPath: "/root"),
                               query: SearchQuery(text: "found"), fileSystem: fs)
        #expect(hits.map(\.entry.name) == ["found.txt"])
    }

    // Breadth-first: shallow results are the ones most likely wanted, and a
    // depth-first walk would spend its budget inside the first subtree.
    @Test("shallower matches come first")
    func breadthFirstOrdering() {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/root"))
        fs.add(directory: "/root", children: ["deep/", "target-shallow.txt"])
        fs.add(directory: "/root/deep", children: ["target-deep.txt"])

        let hits = searchFiles(root: URL(fileURLWithPath: "/root"),
                               query: SearchQuery(text: "target"), fileSystem: fs)
        #expect(hits.first?.entry.name == "target-shallow.txt")
    }
}

@Suite("Search match-all mode")
struct SearchMatchAllTests {
    @Test("match-all collects every entry, while an empty query still finds nothing")
    func matchAllVersusEmpty() {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/root"))
        fs.add(directory: "/root", children: ["a.txt", "b.txt", "sub/"])
        fs.add(directory: "/root/sub", children: ["c.txt"])

        // An empty search box returning the whole disk would be a bug.
        let empty = searchFiles(root: URL(fileURLWithPath: "/root"),
                                query: SearchQuery(text: ""), fileSystem: fs)
        #expect(empty.isEmpty)

        let all = collectTree(root: URL(fileURLWithPath: "/root"), limit: 100,
                              maxDepth: 5, fileSystem: fs)
        #expect(all.count == 4)
    }

    @Test("match-all still prunes noise directories and respects the limit")
    func matchAllStillBounded() {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/root"))
        fs.add(directory: "/root", children: ["keep.txt", "node_modules/"])
        fs.add(directory: "/root/node_modules", children: ["junk.js"])

        let all = collectTree(root: URL(fileURLWithPath: "/root"), limit: 100,
                              maxDepth: 5, fileSystem: fs)
        #expect(all.map(\.entry.name).sorted() == ["keep.txt", "node_modules"])
    }
}
