import Foundation

/// Moving to Trash and back.
///
/// Behind a protocol because EVERY destructive operation depends on it —
/// delete, overwrite, and cross-volume move all route through the Trash so
/// their inverses exist — and the unit tests for the engine and the undo stack
/// must not touch the user's real Trash.
protocol Trashing: Sendable {
    /// Moves `url` to the Trash and returns its resulting location: the handle
    /// `restore` needs, and what the `InverseOperation` records.
    func trash(_ url: URL) throws -> URL
    func restore(from trashURL: URL, to original: URL) throws
}

struct SystemTrashService: Trashing {
    func trash(_ url: URL) throws -> URL {
        var resulting: NSURL?
        // `trashItem`, never `removeItem`: the user's own Trash is the safety
        // net beneath the undo stack, and restoring is then a move rather than
        // a recovery.
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        guard let resulting = resulting as URL? else {
            throw CocoaError(.fileWriteUnknown)
        }
        return resulting
    }

    func restore(from trashURL: URL, to original: URL) throws {
        // The original's parent may itself have been removed since — recreate
        // it rather than failing the undo.
        try FileManager.default.createDirectory(
            at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: trashURL, to: original)
    }
}
