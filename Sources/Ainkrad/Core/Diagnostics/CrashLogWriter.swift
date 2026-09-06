import Foundation

/// Append-only NDJSON diagnostics log with a hard size cap.
///
/// **Never throws and never traps.** This runs from an uncaught-exception
/// handler — a process that is already dying. Anything that could fail a second
/// time there turns a diagnosable crash into an undiagnosable one, so every
/// failure path here degrades to "write nothing" and logs to `os.Logger`.
///
/// Rotation keeps exactly one previous generation (`diagnostics.ndjson.1`).
/// Two files bounded at `maxBytes` each is the whole retention policy: enough
/// to survive a crash loop, small enough never to matter on disk.
final class CrashLogWriter: @unchecked Sendable {
    private let directory: URL
    private let maxBytes: Int
    private let fileManager: FileManager
    private let lock = NSLock()

    let fileURL: URL

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Ainkrad", isDirectory: true)
    }

    init(directory: URL, maxBytes: Int = 1_048_576, fileManager: FileManager = .default) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.fileManager = fileManager
        self.fileURL = directory.appendingPathComponent("diagnostics.ndjson")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func append(_ report: CrashReport) {
        guard let line = try? report.ndjsonLine() else {
            Log.diagnostics.error("Failed to encode a crash report; dropping it")
            return
        }
        lock.lock()
        defer { lock.unlock() }
        rotateIfNeeded(incoming: line.count)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(line)
        } else {
            try? line.write(to: fileURL, options: .atomic)
        }
    }

    func readAll() -> [CrashReport] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        // `try?` per line, deliberately: a crash mid-write leaves a truncated
        // final line, and every good record before it must still be readable.
        return data.split(separator: 0x0A).compactMap {
            try? CrashReport.decode(ndjsonLine: Data($0))
        }
    }

    /// Rotates when the current file plus the incoming line would exceed the cap.
    /// Caller holds `lock`.
    private func rotateIfNeeded(incoming: Int) {
        let size = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard size + incoming > maxBytes else { return }
        let rotated = fileURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: rotated)
        try? fileManager.moveItem(at: fileURL, to: rotated)
    }
}
