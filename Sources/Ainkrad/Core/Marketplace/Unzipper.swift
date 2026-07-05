import Foundation

protocol Unzipper {
    func unzip(_ zip: URL, to destination: URL) throws
}

enum UnzipError: Error, Equatable { case failed(Int32); case unsafeEntry(String) }

/// Extracts a .zip using the system `ditto`, but refuses archives that could
/// escape `destination`: any entry whose name is absolute or contains a `..`
/// path component (ZIP-slip), or any symlink in the extracted tree.
struct DittoUnzipper: Unzipper {
    func unzip(_ zip: URL, to destination: URL) throws {
        // 1. Pre-list entry names and reject traversal/absolute before extracting.
        for name in try entryNames(of: zip) {
            if name.hasPrefix("/") || name.split(separator: "/").contains("..") {
                throw UnzipError.unsafeEntry(name)
            }
        }
        // 2. Extract.
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UnzipError.failed(process.terminationStatus) }
        // 3. Reject any symlink in the extracted tree.
        if let e = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let url as URL in e {
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                    try? FileManager.default.removeItem(at: destination)
                    throw UnzipError.unsafeEntry(url.lastPathComponent)
                }
            }
        }
    }

    /// Lists archive entry names via `/usr/bin/unzip -Z1`.
    private func entryNames(of zip: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", zip.path]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
