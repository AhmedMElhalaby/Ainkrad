import Foundation

/// One filesystem item as the browser sees it. A value type with no live
/// handle: everything here is a snapshot taken at listing time, which is why
/// the list refreshes on FSEvents rather than trusting these to stay true.
struct FileEntry: Identifiable, Equatable, Sendable {
    var url: URL
    var name: String
    var isDirectory: Bool
    var isSymlink: Bool
    var isHidden: Bool
    /// Bytes. Zero for directories — computing directory size is a recursive
    /// walk, deliberately not done during listing.
    var size: Int64
    var modified: Date

    var id: URL { url }

    /// Lowercased extension without the dot, or "" for directories and
    /// extensionless files. Used for the Kind column and icon selection.
    var fileExtension: String {
        isDirectory ? "" : url.pathExtension.lowercased()
    }
}
