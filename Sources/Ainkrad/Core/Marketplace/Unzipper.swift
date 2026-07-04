import Foundation

protocol Unzipper {
    func unzip(_ zip: URL, to destination: URL) throws
}

enum UnzipError: Error, Equatable { case failed(Int32) }

/// Extracts a .zip using the system `ditto` (always present on macOS, handles
/// the archive format Finder/GitHub produce).
struct DittoUnzipper: Unzipper {
    func unzip(_ zip: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UnzipError.failed(process.terminationStatus) }
    }
}
