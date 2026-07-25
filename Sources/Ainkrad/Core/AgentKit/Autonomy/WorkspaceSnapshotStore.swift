import Foundation

/// Copies a file's pre-mutation bytes into a per-checkpoint directory under app
/// support, so a rewind can restore the exact original even across app launches.
/// Best-effort and never-throwing at the boundary: a read/copy failure yields a
/// snapshot the restore path can still act on (matching `EditJournal`'s
/// best-effort philosophy). Directory layout: `<root>/<checkpointID>/<blobName>`.
final class WorkspaceSnapshotStore {
    private let root: URL
    private let fm = FileManager.default

    init(root: URL) {
        self.root = root
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Checkpoints", isDirectory: true)
    }

    func snapshotFile(_ path: String, into checkpointID: UUID) -> FileSnapshot {
        let dir = root.appendingPathComponent(checkpointID.uuidString, isDirectory: true)
        guard fm.fileExists(atPath: path) else {
            return FileSnapshot(path: path, existedBefore: false, blobName: nil)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let blobName = UUID().uuidString + ".blob"
        let dest = dir.appendingPathComponent(blobName)
        if let data = fm.contents(atPath: path) {
            try? data.write(to: dest)
            return FileSnapshot(path: path, existedBefore: true, blobName: blobName)
        }
        return FileSnapshot(path: path, existedBefore: true, blobName: nil)
    }

    func restore(_ snapshot: FileSnapshot, from checkpointID: UUID) {
        if snapshot.existedBefore {
            guard let blobName = snapshot.blobName else { return }
            let blob = root.appendingPathComponent(checkpointID.uuidString).appendingPathComponent(blobName)
            if let data = try? Data(contentsOf: blob) {
                try? data.write(to: URL(fileURLWithPath: snapshot.path))
            }
        } else if fm.fileExists(atPath: snapshot.path) {
            try? fm.removeItem(atPath: snapshot.path)
        }
    }

    func discard(checkpointID: UUID) {
        try? fm.removeItem(at: root.appendingPathComponent(checkpointID.uuidString, isDirectory: true))
    }
}
