import Foundation

/// An item that moved, recorded so it can be moved back.
struct MovedItem: Codable, Equatable, Sendable {
    var from: URL
    var to: URL
}

/// An item in the Trash, and where it came from.
struct TrashedItem: Codable, Equatable, Sendable {
    var original: URL
    var inTrash: URL
}

/// What undoing an operation actually does.
///
/// `.composite` exists because the two genuinely awkward cases — overwrite and
/// cross-volume move — are each TWO undos that must both happen: remove what
/// was written, and put back what was displaced. Modelling them as one action
/// each would either leave the new file behind or fail to restore the old one.
indirect enum InverseAction: Codable, Equatable, Sendable {
    case moveBack([MovedItem])
    case delete([URL])
    case restoreFromTrash([TrashedItem])
    case composite([InverseAction])
}

/// One undoable step: what to do, what it touches, and when it happened.
///
/// `recordedAt` is not decoration — undo refuses to auto-invert an entry whose
/// files have been modified since, and this is the timestamp that comparison
/// is made against.
struct InverseOperation: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    /// Reads as what the USER did ("Copy 3 items"), not as what undoing it
    /// will do — the undo affordance says "Undo <label>".
    var label: String
    var action: InverseAction
    var recordedAt: Date
    /// The paths whose state this entry depends on, for the
    /// externally-modified check.
    var affectedURLs: [URL]
}

extension InverseOperation {
    private static func itemLabel(_ verb: String, _ count: Int) -> String {
        "\(verb) \(count) item\(count == 1 ? "" : "s")"
    }

    /// Same-volume move: the inverse is simply the reverse move.
    static func forMove(items: [MovedItem], at now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Move", items.count),
            action: .moveBack(items.map { MovedItem(from: $0.to, to: $0.from) }),
            recordedAt: now,
            affectedURLs: items.map(\.to))
    }

    /// Copy: delete what we created. The sources were never touched.
    static func forCopy(created: [URL], at now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Copy", created.count),
            action: .delete(created),
            recordedAt: now,
            affectedURLs: created)
    }

    /// Overwrite: the displaced file was trashed BEFORE the write, so undo
    /// removes the new file and restores the old one — in that order, since
    /// restoring first would collide with the file still occupying the path.
    static func forOverwrite(created: [URL], overwritten: [TrashedItem],
                             at now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Replace", created.count),
            action: .composite([.delete(created), .restoreFromTrash(overwritten)]),
            recordedAt: now,
            affectedURLs: created)
    }

    /// Cross-volume move: implemented as copy-then-trash-source, so the
    /// inverse is delete-the-copies plus restore-the-sources.
    static func forCrossVolumeMove(created: [URL], trashedSources: [TrashedItem],
                                   at now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Move", created.count),
            action: .composite([.delete(created), .restoreFromTrash(trashedSources)]),
            recordedAt: now,
            affectedURLs: created)
    }

    static func forTrash(items: [TrashedItem], at now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: itemLabel("Delete", items.count),
            action: .restoreFromTrash(items),
            recordedAt: now,
            affectedURLs: items.map(\.original))
    }

    static func forRename(from original: URL, to renamed: URL,
                          at now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: "Rename",
            action: .moveBack([MovedItem(from: renamed, to: original)]),
            recordedAt: now,
            affectedURLs: [renamed])
    }

    static func forCreateFolder(at url: URL, now: Date = Date()) -> InverseOperation {
        InverseOperation(
            label: "New folder",
            action: .delete([url]),
            recordedAt: now,
            affectedURLs: [url])
    }
}
