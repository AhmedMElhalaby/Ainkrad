import Foundation

/// One planned rename, for the preview table.
struct BatchRenamePlanItem: Identifiable, Equatable, Sendable {
    var entry: FileEntry
    var newName: String
    /// Why this row will not be applied, if it won't.
    var problem: Problem?

    var id: URL { entry.url }
    var isChanged: Bool { newName != entry.name && problem == nil }

    enum Problem: Equatable, Sendable {
        case unchanged
        case emptyResult
        case collidesWithExisting
        case collidesWithAnotherRename
    }
}

enum BatchRenameMode: String, CaseIterable, Sendable {
    case findReplace
    case addPrefix
    case addSuffix
    case numberSequentially
}

/// Computes the full plan BEFORE anything is applied.
///
/// A preview is not a nicety here: batch rename is the highest-leverage and
/// highest-blast-radius operation in the app, and the failure mode is renaming
/// 400 files correctly-but-wrongly. Seeing the result first is the difference
/// between confidence and an undo scramble.
///
/// Collisions are detected in BOTH directions — against files already on disk,
/// and against other rows in the same batch, which is the case a naive
/// implementation misses and which silently destroys data.
func batchRenamePlan(entries: [FileEntry], mode: BatchRenameMode,
                     find: String, replace: String,
                     existingNames: Set<String>,
                     startNumber: Int = 1) -> [BatchRenamePlanItem] {
    var plan: [BatchRenamePlanItem] = []
    var claimed: Set<String> = []

    for (offset, entry) in entries.enumerated() {
        let newName = renamedName(entry: entry, mode: mode, find: find,
                                  replace: replace, index: startNumber + offset)

        var problem: BatchRenamePlanItem.Problem?
        if newName.isEmpty {
            problem = .emptyResult
        } else if newName == entry.name {
            problem = .unchanged
        } else if claimed.contains(newName) {
            problem = .collidesWithAnotherRename
        } else if existingNames.contains(newName) && newName != entry.name {
            problem = .collidesWithExisting
        }

        if problem == nil { claimed.insert(newName) }
        plan.append(BatchRenamePlanItem(entry: entry, newName: newName, problem: problem))
    }
    return plan
}

private func renamedName(entry: FileEntry, mode: BatchRenameMode,
                         find: String, replace: String, index: Int) -> String {
    let name = entry.name
    switch mode {
    case .findReplace:
        guard !find.isEmpty else { return name }
        return name.replacingOccurrences(of: find, with: replace)

    case .addPrefix:
        return replace + name

    case .addSuffix:
        // Before the extension, not after it — "photo.jpg" + "-edited" must
        // give "photo-edited.jpg", not "photo.jpg-edited".
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        return ext.isEmpty ? stem + replace : "\(stem)\(replace).\(ext)"

    case .numberSequentially:
        let ext = (name as NSString).pathExtension
        let base = replace.isEmpty ? (name as NSString).deletingPathExtension : replace
        let numbered = "\(base) \(index)"
        return ext.isEmpty ? numbered : "\(numbered).\(ext)"
    }
}
