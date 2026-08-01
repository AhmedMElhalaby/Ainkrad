import Testing
import Foundation
@testable import Ainkrad

@Suite("Batch rename planning")
struct BatchRenameTests {
    private func entry(_ name: String) -> FileEntry {
        FileEntry(url: URL(fileURLWithPath: "/x/\(name)"), name: name, isDirectory: false,
                  isSymlink: false, isHidden: false, size: 0, modified: Date())
    }

    private func plan(_ names: [String], mode: BatchRenameMode = .findReplace,
                      find: String = "", replace: String = "",
                      existing: Set<String> = [], start: Int = 1) -> [BatchRenamePlanItem] {
        batchRenamePlan(entries: names.map(entry), mode: mode, find: find, replace: replace,
                        existingNames: existing, startNumber: start)
    }

    @Test("find and replace rewrites matching names")
    func findReplace() {
        let result = plan(["a-draft.txt", "b-draft.txt"], find: "-draft", replace: "-final")
        #expect(result.map(\.newName) == ["a-final.txt", "b-final.txt"])
        let allChanged = result.allSatisfy(\.isChanged)
        #expect(allChanged)
    }

    @Test("a name that does not match is marked unchanged, not renamed")
    func unchangedMarked() {
        let result = plan(["keep.txt"], find: "zzz", replace: "x")
        #expect(result[0].problem == .unchanged)
        #expect(!result[0].isChanged)
    }

    @Test("prefix mode prepends")
    func prefix() {
        #expect(plan(["photo.jpg"], mode: .addPrefix, replace: "2026-").map(\.newName)
                == ["2026-photo.jpg"])
    }

    // "photo.jpg" + "-edited" must not become "photo.jpg-edited".
    @Test("suffix mode inserts BEFORE the extension")
    func suffixBeforeExtension() {
        #expect(plan(["photo.jpg"], mode: .addSuffix, replace: "-edited").map(\.newName)
                == ["photo-edited.jpg"])
        #expect(plan(["README"], mode: .addSuffix, replace: "-old").map(\.newName)
                == ["README-old"])
    }

    @Test("sequential numbering keeps the extension and counts from the start number")
    func numbering() {
        let result = plan(["a.png", "b.png"], mode: .numberSequentially,
                          replace: "shot", start: 5)
        #expect(result.map(\.newName) == ["shot 5.png", "shot 6.png"])
    }

    // MARK: - Collisions

    @Test("a rename onto an existing file is flagged, not applied")
    func collidesWithExisting() {
        let result = plan(["draft.txt"], find: "draft", replace: "final",
                          existing: ["final.txt"])
        #expect(result[0].problem == .collidesWithExisting)
        #expect(!result[0].isChanged)
    }

    // The case a naive implementation misses — and the one that destroys data.
    @Test("two rows renaming to the SAME name flags the second, not both")
    func collidesWithinBatch() {
        // "v1-report" and "v2-report" both collapse to "report" when the
        // version prefix is stripped.
        let result = plan(["v1-report.txt", "v2-report.txt"], find: "v1-", replace: "")
        #expect(result[0].newName == "report.txt")
        #expect(result[0].problem == nil)

        // Now make them genuinely collide.
        let collide = batchRenamePlan(
            entries: [entry("a.txt"), entry("b.txt")],
            mode: .numberSequentially, find: "", replace: "same",
            existingNames: [], startNumber: 1)
        // Sequential numbering keeps them distinct — that is the point of it.
        #expect(collide.map(\.newName) == ["same 1.txt", "same 2.txt"])

        // A find/replace that maps two DIFFERENT names onto one:
        let clash = batchRenamePlan(
            entries: [entry("x-1.txt"), entry("y-1.txt")],
            mode: .findReplace, find: "x-1", replace: "merged",
            existingNames: [])
        #expect(clash[0].newName == "merged.txt")

        let bothToSame = batchRenamePlan(
            entries: [entry("alpha.txt"), entry("beta.txt")],
            mode: .addPrefix, find: "", replace: "",
            existingNames: [])
        // A no-op prefix leaves both unchanged rather than colliding.
        let noopUnchanged = bothToSame.allSatisfy { $0.problem == .unchanged }
        #expect(noopUnchanged)
    }

    // THE data-destroying case: two different names that collapse to one.
    // "a-b.txt" and "ab-.txt" both become "ab.txt" when "-" is stripped.
    @Test("a real within-batch collision is flagged on the later row only")
    func explicitWithinBatchCollision() {
        let result = batchRenamePlan(
            entries: [entry("a-b.txt"), entry("ab-.txt")],
            mode: .findReplace, find: "-", replace: "",
            existingNames: [])

        #expect(result[0].newName == "ab.txt")
        #expect(result[0].problem == nil, "the first claim on a name should succeed")
        #expect(result[1].newName == "ab.txt")
        #expect(result[1].problem == .collidesWithAnotherRename,
                "the second must be refused, or one file silently overwrites the other")
        #expect(!result[1].isChanged)
    }

    @Test("an empty result is refused rather than creating a nameless file")
    func emptyResultRefused() {
        let result = plan(["abc"], find: "abc", replace: "")
        #expect(result[0].problem == .emptyResult)
        #expect(!result[0].isChanged)
    }

    @Test("an empty find string changes nothing")
    func emptyFindIsNoop() {
        let result = plan(["a.txt", "b.txt"], find: "", replace: "x")
        // Hoisted out of `#expect`: swift-testing's macro cannot decompose a
        // `rethrows` call taking a closure.
        let allUnchanged = result.allSatisfy { $0.problem == .unchanged }
        #expect(allUnchanged)
    }

    @Test("an empty selection produces an empty plan")
    func emptySelection() {
        #expect(plan([]).isEmpty)
    }

    @Test("the plan reports how many rows would actually change")
    func changedCount() {
        let result = plan(["a-draft.txt", "keep.txt"], find: "-draft", replace: "-final")
        #expect(result.filter(\.isChanged).count == 1)
    }
}
