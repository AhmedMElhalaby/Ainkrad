import Foundation

/// The ONLY seam through which Files touches the filesystem. Everything above
/// it — sorting, history, the stores, the views — depends on this protocol and
/// is therefore testable against an in-memory fake with no disk.
protocol FileSystemServing: Sendable {
    /// Immediate children of `directory`, unsorted and unfiltered.
    /// Throws if the directory is missing or unreadable.
    func contents(of directory: URL) throws -> [FileEntry]
    func isDirectory(_ url: URL) -> Bool
    func exists(_ url: URL) -> Bool
    var homeDirectory: URL { get }
}
