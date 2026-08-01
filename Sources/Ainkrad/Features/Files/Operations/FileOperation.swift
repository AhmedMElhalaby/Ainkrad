import Foundation

/// What to do when a destination name is already taken.
enum ConflictPolicy: String, Sendable, Codable {
    case ask, replace, keepBoth, skip, merge
}

enum FileOperationKind: Sendable, Equatable {
    case copy
    case move
    case rename(newName: String)
    case createFolder(name: String)
    case trash
}

/// A described intent, not an execution. Values are cheap to build, test and
/// queue; `FileOperationEngine` is the only thing that performs them.
struct FileOperation: Identifiable, Sendable {
    let id = UUID()
    var kind: FileOperationKind
    var sources: [URL]
    /// Where the result lands. `nil` for rename and trash, which act in place.
    var destinationDirectory: URL?
    var policy: ConflictPolicy = .ask
}

/// "a.txt" → "a 2.txt" → "a 3.txt", skipping names already present.
///
/// Splits on the LAST dot only, and never treats a leading dot as an extension
/// boundary: ".gitignore" is a whole name, so it must suffix to ".gitignore 2"
/// rather than " 2.gitignore".
func uniqueDestinationName(for name: String, existing: Set<String>) -> String {
    guard existing.contains(name) else { return name }

    let isDotfile = name.hasPrefix(".")
    let body = isDotfile ? String(name.dropFirst()) : name
    let ext = (body as NSString).pathExtension
    let stem = (body as NSString).deletingPathExtension
    let prefix = isDotfile ? "." : ""

    var index = 2
    while true {
        let candidate = ext.isEmpty
            ? "\(prefix)\(stem) \(index)"
            : "\(prefix)\(stem) \(index).\(ext)"
        if !existing.contains(candidate) { return candidate }
        index += 1
    }
}
