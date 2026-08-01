import Foundation

/// Why an undo could not be applied. Both cases are surfaced to the user —
/// silently doing nothing is what makes an undo stack untrustworthy.
enum UndoRefusal: Equatable {
    /// A file this entry touches has changed since the operation. Auto-
    /// inverting would clobber newer content in the name of undo, which is
    /// worse than not undoing.
    case externallyModified(URL)
    /// The volume is gone (ejected disk). The entry is dropped rather than
    /// left as a landmine that fails at the next ⌘Z.
    case unavailable(URL)

    var message: String {
        switch self {
        case .externallyModified(let url):
            return "“\(url.lastPathComponent)” changed since then — undo would overwrite newer content."
        case .unavailable(let url):
            return "“\(url.lastPathComponent)” is no longer available — that step was dropped."
        }
    }
}

extension FileOperationEngine {
    /// Applies the most recent inverse, or explains why it can't.
    @discardableResult
    func undo() -> UndoRefusal? {
        guard let entry = undoStack.entries.last else { return nil }

        if let refusal = refusal(for: entry) {
            // An unavailable volume is permanent for this entry: drop it so
            // the next ⌘Z reaches something that can actually be applied. An
            // externally-modified entry STAYS — the user may revert the file
            // and try again.
            if case .unavailable = refusal { undoStack.drop(entry.id) }
            return refusal
        }

        _ = undoStack.popForUndo()
        apply(entry.action)
        undoStack.pushRedo(redoCounterpart(of: entry))
        return nil
    }

    @discardableResult
    func redo() -> UndoRefusal? {
        guard let entry = undoStack.redoEntries.last else { return nil }
        _ = undoStack.popForRedo()
        apply(entry.action)
        return nil
    }

    /// The check that makes undo trustworthy: refuse when the world moved on.
    private func refusal(for entry: InverseOperation) -> UndoRefusal? {
        for url in entry.affectedURLs {
            guard let modified = mutatorModificationDate(url) else {
                // Missing is fine for a `.delete` inverse (nothing to remove),
                // so absence alone is not a refusal — only an unreachable
                // VOLUME is.
                if mutatorVolumeIdentifier(url) == nil { return .unavailable(url) }
                continue
            }
            // A tolerance, not equality: filesystem timestamps have coarse
            // resolution and the write completes microseconds after we record.
            if modified.timeIntervalSince(entry.recordedAt) > 1.0 {
                return .externallyModified(url)
            }
        }
        return nil
    }

    private func apply(_ action: InverseAction) {
        switch action {
        case .moveBack(let items):
            for item in items { try? mutatorMove(item.from, item.to) }
        case .delete(let urls):
            for url in urls { try? mutatorRemove(url) }
        case .restoreFromTrash(let items):
            for item in items { try? trashRestore(item.inTrash, item.original) }
        case .composite(let actions):
            // Order matters: remove what was written BEFORE restoring what was
            // displaced, or the restore collides with the file still there.
            for nested in actions { apply(nested) }
        }
    }

    /// Undoing a copy means deleting the copies; redoing it would mean copying
    /// again, which we cannot reconstruct from the inverse alone. So redo
    /// replays the INVERSE OF THE INVERSE where that is well-defined, and is
    /// otherwise a no-op recorded for label purposes only.
    private func redoCounterpart(of entry: InverseOperation) -> InverseOperation {
        switch entry.action {
        case .moveBack(let items):
            return InverseOperation(
                id: entry.id, label: entry.label,
                action: .moveBack(items.map { MovedItem(from: $0.to, to: $0.from) }),
                recordedAt: Date(), affectedURLs: items.map(\.from))
        default:
            return entry
        }
    }
}
