import Foundation
import Observation

/// A conflict the engine needs answered before it can proceed.
struct ConflictQuestion: Sendable {
    var name: String
    var source: URL
    var destination: URL
    var isDirectory: Bool
}

struct ConflictAnswer: Sendable {
    var policy: ConflictPolicy
    var applyToAll: Bool

    static let skipOnce = ConflictAnswer(policy: .skip, applyToAll: false)
}

/// Asked when a destination is occupied and the operation's policy is `.ask`.
typealias ConflictResolving = @MainActor (ConflictQuestion) async -> ConflictAnswer

/// Executes `FileOperation`s: serialised per volume, cancellable, and — the
/// point of the whole design — recording an `InverseOperation` before it
/// commits, so every mutation is undoable regardless of who initiated it.
@MainActor
@Observable
final class FileOperationEngine {
    private let mutator: any FileMutating
    private let trash: any Trashing
    let undoStack: UndoStack

    private let serializer = VolumeSerializer()

    /// Jobs currently running. The operations panel binds to this; jobs
    /// deliberately outlive the pane that started them.
    private(set) var activeJobs: [OperationProgress] = []

    init(mutator: any FileMutating, trash: any Trashing, undoStack: UndoStack) {
        self.mutator = mutator
        self.trash = trash
        self.undoStack = undoStack
    }

    // MARK: - Seams for the undo extension
    //
    // `mutator` and `trash` are private so nothing outside the engine mutates
    // the filesystem behind its back. The undo path lives in an extension for
    // file-size reasons, so it reaches them through these narrow accessors
    // rather than by widening the stored properties.

    func mutatorMove(_ source: URL, _ destination: URL) throws {
        try mutator.moveItem(at: source, to: destination)
    }

    func mutatorRemove(_ url: URL) throws {
        try mutator.removeItem(at: url)
    }

    func mutatorModificationDate(_ url: URL) -> Date? {
        mutator.modificationDate(of: url)
    }

    func mutatorVolumeIdentifier(_ url: URL) -> String? {
        mutator.volumeIdentifier(for: url)
    }

    func trashRestore(_ inTrash: URL, _ original: URL) throws {
        try trash.restore(from: inTrash, to: original)
    }

    // MARK: - Submission

    @discardableResult
    func submit(_ operation: FileOperation,
                conflictResolver: ConflictResolving? = nil) async -> OperationResult {
        let progress = OperationProgress(label: label(for: operation),
                                         totalItems: max(operation.sources.count, 1))
        activeJobs.append(progress)
        defer {
            progress.finish()
            activeJobs.removeAll { $0.id == progress.id }
        }

        let volume = volumeKey(for: operation)
        return await serializer.serialize(volume: volume) { [weak self] in
            guard let self else {
                return OperationResult(succeeded: 0, skipped: 0, failures: [], wasCancelled: true)
            }
            return await self.execute(operation, progress: progress,
                                      conflictResolver: conflictResolver)
        }
    }

    /// Which queue this operation belongs on. Destination volume when there is
    /// one (that's where the writing happens), else the first source's.
    private func volumeKey(for operation: FileOperation) -> String {
        let reference = operation.destinationDirectory ?? operation.sources.first
        guard let reference else { return "none" }
        return mutator.volumeIdentifier(for: reference) ?? "unknown"
    }

    private func label(for operation: FileOperation) -> String {
        switch operation.kind {
        case .copy: return "Copying \(operation.sources.count) item\(operation.sources.count == 1 ? "" : "s")"
        case .move: return "Moving \(operation.sources.count) item\(operation.sources.count == 1 ? "" : "s")"
        case .rename: return "Renaming"
        case .batchRename: return "Renaming \(operation.sources.count) item\(operation.sources.count == 1 ? "" : "s")"
        case .createFolder: return "Creating folder"
        case .trash: return "Deleting \(operation.sources.count) item\(operation.sources.count == 1 ? "" : "s")"
        }
    }

    // MARK: - Execution

    private func execute(_ operation: FileOperation, progress: OperationProgress,
                         conflictResolver: ConflictResolving?) async -> OperationResult {
        switch operation.kind {
        case .copy, .move:
            return await transfer(operation, progress: progress, conflictResolver: conflictResolver)
        case .rename(let newName):
            return rename(operation, to: newName)
        case .batchRename(let newNames):
            return batchRename(operation, to: newNames, progress: progress)
        case .createFolder(let name):
            return createFolder(operation, named: name)
        case .trash:
            return trashItems(operation, progress: progress)
        }
    }

    /// Copy and move share everything except what happens to the source, so
    /// they share one path rather than two near-identical ones that drift.
    private func transfer(_ operation: FileOperation, progress: OperationProgress,
                          conflictResolver: ConflictResolving?) async -> OperationResult {
        guard let destinationDirectory = operation.destinationDirectory else {
            return OperationResult(succeeded: 0, skipped: 0, failures: [], wasCancelled: false)
        }
        let isMove = operation.kind == .move

        var created: [URL] = []
        var moved: [MovedItem] = []
        var overwritten: [TrashedItem] = []
        var trashedSources: [TrashedItem] = []
        var failures: [OperationFailure] = []
        var skipped = 0
        var blanketPolicy: ConflictPolicy? =
            operation.policy == .ask ? nil : operation.policy
        var sawCrossVolume = false

        for source in operation.sources {
            if progress.isCancelled { break }

            var destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)

            if mutator.fileExists(destination) {
                let policy: ConflictPolicy
                if let blanketPolicy {
                    policy = blanketPolicy
                } else if let conflictResolver {
                    let answer = await conflictResolver(ConflictQuestion(
                        name: source.lastPathComponent, source: source,
                        destination: destination, isDirectory: mutator.isDirectory(source)))
                    if answer.applyToAll { blanketPolicy = answer.policy }
                    policy = answer.policy
                } else {
                    // No resolver and no policy: skip rather than silently
                    // destroying something.
                    policy = .skip
                }

                switch policy {
                case .skip, .ask:
                    skipped += 1
                    progress.advance()
                    continue
                case .keepBoth:
                    let unique = uniqueDestinationName(
                        for: source.lastPathComponent,
                        existing: mutator.childNames(of: destinationDirectory))
                    destination = destinationDirectory.appendingPathComponent(unique)
                case .replace, .merge:
                    // Trash the displaced item FIRST, so the inverse can
                    // restore it. This is the case Finder gets wrong and the
                    // reason the whole scheme routes through the Trash.
                    do {
                        let inTrash = try trash.trash(destination)
                        overwritten.append(TrashedItem(original: destination, inTrash: inTrash))
                    } catch {
                        failures.append(OperationFailure(
                            url: destination, reason: error.localizedDescription))
                        progress.advance()
                        continue
                    }
                }
            }

            let sourceVolume = mutator.volumeIdentifier(for: source)
            let destinationVolume = mutator.volumeIdentifier(for: destinationDirectory)
            // Unknown volumes are treated as different: the cross-volume path
            // is the invertible one, so it is the safe assumption.
            let isCrossVolume = sourceVolume == nil || destinationVolume == nil
                || sourceVolume != destinationVolume

            do {
                if isMove && !isCrossVolume {
                    try mutator.moveItem(at: source, to: destination)
                    moved.append(MovedItem(from: source, to: destination))
                } else {
                    try mutator.copyItem(at: source, to: destination)
                    created.append(destination)
                    if isMove {
                        // Copy-then-TRASH, never remove: the source must stay
                        // recoverable for the inverse.
                        sawCrossVolume = true
                        let inTrash = try trash.trash(source)
                        trashedSources.append(TrashedItem(original: source, inTrash: inTrash))
                    }
                }
            } catch {
                // One bad item does not abort the batch.
                failures.append(OperationFailure(url: source, reason: error.localizedDescription))
                progress.advance()
                continue
            }
            progress.advance()
        }

        // Record an inverse covering ONLY what actually completed — a
        // cancelled job that under-records would leave undo unable to restore
        // the work it did do.
        recordInverse(isMove: isMove, sawCrossVolume: sawCrossVolume,
                      created: created, moved: moved,
                      overwritten: overwritten, trashedSources: trashedSources,
                      sources: operation.sources)

        return OperationResult(succeeded: created.count + moved.count, skipped: skipped,
                               failures: failures, wasCancelled: progress.isCancelled)
    }

    private func recordInverse(isMove: Bool, sawCrossVolume: Bool, created: [URL],
                               moved: [MovedItem], overwritten: [TrashedItem],
                               trashedSources: [TrashedItem], sources: [URL]) {
        guard !created.isEmpty || !moved.isEmpty else { return }

        if !overwritten.isEmpty {
            undoStack.push(.forOverwrite(created: created + moved.map(\.to),
                                         overwritten: overwritten, sources: sources))
        } else if isMove && sawCrossVolume {
            undoStack.push(.forCrossVolumeMove(created: created, trashedSources: trashedSources))
        } else if isMove {
            undoStack.push(.forMove(items: moved))
        } else {
            undoStack.push(.forCopy(created: created, sources: sources))
        }
    }

    private func rename(_ operation: FileOperation, to newName: String) -> OperationResult {
        guard let source = operation.sources.first else {
            return OperationResult(succeeded: 0, skipped: 0, failures: [], wasCancelled: false)
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        guard !mutator.fileExists(destination) else {
            return OperationResult(succeeded: 0, skipped: 0, failures: [OperationFailure(
                url: destination, reason: "A file named “\(newName)” already exists.")],
                wasCancelled: false)
        }
        do {
            try mutator.moveItem(at: source, to: destination)
            undoStack.push(.forRename(from: source, to: destination))
            return OperationResult(succeeded: 1, skipped: 0, failures: [], wasCancelled: false)
        } catch {
            return OperationResult(succeeded: 0, skipped: 0, failures: [OperationFailure(
                url: source, reason: error.localizedDescription)], wasCancelled: false)
        }
    }

    /// Many renames, ONE undo entry.
    ///
    /// Submitting a rename per row (what the batch sheet did first) works, but
    /// it means undoing a 200-file rename is 200 ⌘Z — technically reversible,
    /// practically not. Recording a single inverse over every pair that landed
    /// makes ⌘Z put the whole batch back.
    ///
    /// A row that fails does NOT abort the rest, matching `transfer`: the
    /// inverse covers exactly what completed, so a partial batch is still
    /// wholly undoable.
    private func batchRename(_ operation: FileOperation, to newNames: [String],
                             progress: OperationProgress) -> OperationResult {
        guard newNames.count == operation.sources.count else {
            // Positional arrays out of step would rename files under each
            // other's names — refuse the whole thing rather than guess.
            return OperationResult(succeeded: 0, skipped: 0, failures: [OperationFailure(
                url: operation.sources.first ?? URL(fileURLWithPath: "/"),
                reason: "Batch rename received \(newNames.count) names for \(operation.sources.count) files.")],
                wasCancelled: false)
        }

        var moved: [MovedItem] = []
        var failures: [OperationFailure] = []

        for (source, newName) in zip(operation.sources, newNames) {
            if progress.isCancelled { break }
            let destination = source.deletingLastPathComponent().appendingPathComponent(newName)

            guard !mutator.fileExists(destination) else {
                // The planner already filtered collisions, but the disk can
                // change between preview and apply.
                failures.append(OperationFailure(
                    url: destination, reason: "A file named “\(newName)” already exists."))
                progress.advance()
                continue
            }
            do {
                try mutator.moveItem(at: source, to: destination)
                moved.append(MovedItem(from: source, to: destination))
            } catch {
                failures.append(OperationFailure(url: source, reason: error.localizedDescription))
            }
            progress.advance()
        }

        if !moved.isEmpty { undoStack.push(.forBatchRename(items: moved)) }
        return OperationResult(succeeded: moved.count, skipped: 0,
                               failures: failures, wasCancelled: progress.isCancelled)
    }

    private func createFolder(_ operation: FileOperation, named name: String) -> OperationResult {
        guard let parent = operation.destinationDirectory else {
            return OperationResult(succeeded: 0, skipped: 0, failures: [], wasCancelled: false)
        }
        let url = parent.appendingPathComponent(name)
        guard !mutator.fileExists(url) else {
            return OperationResult(succeeded: 0, skipped: 0, failures: [OperationFailure(
                url: url, reason: "A folder named “\(name)” already exists.")],
                wasCancelled: false)
        }
        do {
            try mutator.createDirectory(at: url)
            undoStack.push(.forCreateFolder(at: url))
            return OperationResult(succeeded: 1, skipped: 0, failures: [], wasCancelled: false)
        } catch {
            return OperationResult(succeeded: 0, skipped: 0, failures: [OperationFailure(
                url: url, reason: error.localizedDescription)], wasCancelled: false)
        }
    }

    private func trashItems(_ operation: FileOperation,
                            progress: OperationProgress) -> OperationResult {
        var items: [TrashedItem] = []
        var failures: [OperationFailure] = []

        for source in operation.sources {
            if progress.isCancelled { break }
            do {
                let inTrash = try trash.trash(source)
                items.append(TrashedItem(original: source, inTrash: inTrash))
            } catch {
                failures.append(OperationFailure(url: source, reason: error.localizedDescription))
            }
            progress.advance()
        }

        if !items.isEmpty { undoStack.push(.forTrash(items: items)) }
        return OperationResult(succeeded: items.count, skipped: 0,
                               failures: failures, wasCancelled: progress.isCancelled)
    }
}
