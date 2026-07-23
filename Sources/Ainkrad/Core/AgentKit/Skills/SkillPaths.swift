import Foundation
import AinkradHostRuntime

/// Resolves the on-disk layout for skills (global, app-managed):
///   Skills/<name>/SKILL.md            installed (marketplace) or local
///   Skills/_proposed/<name>/SKILL.md  agent-drafted, pending approval
///
/// `root` is injectable so tests can point at a per-test temp directory and
/// never touch the real App Support tree; `defaultRoot()` resolves the real
/// location for production use.
struct SkillPaths {
    let root: URL
    init(root: URL) { self.root = root }

    var proposedRoot: URL { root.appendingPathComponent("_proposed", isDirectory: true) }

    func skillDir(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
    func skillFile(_ name: String) -> URL { skillDir(name).appendingPathComponent("SKILL.md") }
    func proposedDir(_ name: String) -> URL { proposedRoot.appendingPathComponent(name, isDirectory: true) }
    func proposedFile(_ name: String) -> URL { proposedDir(name).appendingPathComponent("SKILL.md") }

    /// `~/Library/Application Support/<bundle-id>/Skills` (mirrors
    /// `FileDocumentStore.defaultDocumentsURL`, but the `Skills` subdir).
    static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Skills", isDirectory: true)
    }

    /// Creates `root` and `proposedRoot` on disk if they don't already exist.
    /// Call once before first use (e.g. at skill-discovery startup); safe to
    /// call repeatedly.
    func ensureDirectoriesExist(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: proposedRoot, withIntermediateDirectories: true)
    }
}
