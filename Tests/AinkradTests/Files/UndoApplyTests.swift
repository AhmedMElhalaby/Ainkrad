import Testing
import Foundation
import AinkradHostRuntime
@testable import Ainkrad

@MainActor
@Suite("Undo application and refusals")
struct UndoApplyTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private func makeEngine(_ mutator: InMemoryFileMutator, trash: InMemoryTrash = InMemoryTrash())
        -> (FileOperationEngine, UndoStack, InMemoryTrash) {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        return (FileOperationEngine(mutator: mutator, trash: trash, undoStack: stack), stack, trash)
    }

    @Test("undoing a copy deletes the copy and leaves the original")
    func undoCopy() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "data")
        mutator.addDirectory("/b")
        let (engine, stack, _) = makeEngine(mutator)

        _ = await engine.submit(FileOperation(
            kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))
        #expect(mutator.fileExists(url("/b/one.txt")))

        #expect(engine.undo() == nil)
        #expect(!mutator.fileExists(url("/b/one.txt")))
        #expect(mutator.fileExists(url("/a/one.txt")))
        #expect(!stack.canUndo)
        #expect(stack.canRedo)
    }

    @Test("undoing a move puts the file back where it started")
    func undoMove() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "data")
        mutator.addDirectory("/b")
        let (engine, _, _) = makeEngine(mutator)

        _ = await engine.submit(FileOperation(
            kind: .move, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))
        #expect(engine.undo() == nil)

        #expect(mutator.contents(of: "/a/one.txt") == "data")
        #expect(!mutator.fileExists(url("/b/one.txt")))
    }

    // The headline promise of the whole design: an overwrite is recoverable.
    @Test("undoing an overwrite restores the ORIGINAL content")
    func undoOverwriteRestoresOriginal() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "new")
        mutator.addFile("/b/one.txt", contents: "original")
        let trash = InMemoryTrash()
        let (engine, _, _) = makeEngine(mutator, trash: trash)

        _ = await engine.submit(FileOperation(
            kind: .copy, sources: [url("/a/one.txt")],
            destinationDirectory: url("/b"), policy: .replace))
        #expect(mutator.contents(of: "/b/one.txt") == "new")

        #expect(engine.undo() == nil)
        // The fake trash records the restore; the real one moves bytes back.
        #expect(trash.restored == [url("/b/one.txt")])
    }

    @Test("undoing a delete restores from the Trash")
    func undoDelete() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt")
        let trash = InMemoryTrash()
        let (engine, _, _) = makeEngine(mutator, trash: trash)

        _ = await engine.submit(FileOperation(
            kind: .trash, sources: [url("/a/one.txt")], destinationDirectory: nil))
        #expect(engine.undo() == nil)
        #expect(trash.restored == [url("/a/one.txt")])
    }

    @Test("undoing a new folder removes it")
    func undoCreateFolder() async {
        let mutator = InMemoryFileMutator()
        mutator.addDirectory("/a")
        let (engine, _, _) = makeEngine(mutator)

        _ = await engine.submit(FileOperation(
            kind: .createFolder(name: "fresh"), sources: [], destinationDirectory: url("/a")))
        #expect(mutator.isDirectory(url("/a/fresh")))
        #expect(engine.undo() == nil)
        #expect(!mutator.isDirectory(url("/a/fresh")))
    }

    @Test("undo with an empty stack is a harmless no-op")
    func undoEmpty() {
        let (engine, _, _) = makeEngine(InMemoryFileMutator())
        #expect(engine.undo() == nil)
    }

    // MARK: - Refusals

    @Test("undo refuses when the file changed since the operation")
    func refusesExternallyModified() async {
        let mutator = ModifiableMutator()
        mutator.addFile("/a/one.txt", contents: "data")
        mutator.addDirectory("/b")
        let (engine, stack, _) = makeEngine(mutator)

        _ = await engine.submit(FileOperation(
            kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))

        // Someone else wrote to the copy after we made it.
        mutator.overriddenDates["/b/one.txt"] = Date().addingTimeInterval(600)

        let refusal = engine.undo()
        #expect(refusal == .externallyModified(url("/b/one.txt")))
        // The entry SURVIVES: the user may revert the file and retry.
        #expect(stack.canUndo)
        #expect(mutator.fileExists(url("/b/one.txt")))
    }

    @Test("undo drops an entry whose volume has gone away")
    func dropsUnavailableVolume() async {
        let mutator = ModifiableMutator()
        mutator.addFile("/a/one.txt")
        mutator.addDirectory("/b")
        let (engine, stack, _) = makeEngine(mutator)

        _ = await engine.submit(FileOperation(
            kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))

        // Simulate an ejected disk: the path resolves to no volume and has no
        // modification date.
        mutator.unavailablePaths.insert("/b/one.txt")

        let refusal = engine.undo()
        #expect(refusal == .unavailable(url("/b/one.txt")))
        // Dropped, so the next ⌘Z reaches something applicable instead of
        // hitting the same landmine forever.
        #expect(!stack.canUndo)
    }
}

/// Mutator whose modification dates and volume availability can be forced,
/// so the two refusal paths are testable without a real ejectable disk.
private final class ModifiableMutator: InMemoryFileMutator, @unchecked Sendable {
    var overriddenDates: [String: Date] = [:]
    var unavailablePaths: Set<String> = []

    override func modificationDate(of url: URL) -> Date? {
        if unavailablePaths.contains(url.path) { return nil }
        if let forced = overriddenDates[url.path] { return forced }
        return super.modificationDate(of: url)
    }

    override func volumeIdentifier(for url: URL) -> String? {
        if unavailablePaths.contains(url.path) { return nil }
        return super.volumeIdentifier(for: url)
    }
}
