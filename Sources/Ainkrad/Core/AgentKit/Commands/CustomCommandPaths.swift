import Foundation

/// Resolves the on-disk layout for custom commands:
///   <userRoot>/<name>.md               global (app-managed, all workspaces)
///   <workspace>/.ainkrad/commands/*.md  project-scoped (checked into the repo)
/// `projectRoot` is nil when there is no active workspace folder. Both roots are
/// injectable so tests point at per-test temp dirs; `defaultUserRoot()` resolves
/// the real Application Support location (mirrors `SkillPaths.defaultRoot()`).
struct CustomCommandPaths {
    let userRoot: URL
    let projectRoot: URL?

    init(userRoot: URL, projectRoot: URL?) {
        self.userRoot = userRoot
        self.projectRoot = projectRoot
    }

    /// Every `*.md` under each root, tagged with its scope, sorted by filename
    /// per root for deterministic ordering. A missing directory yields no files
    /// (never an error), matching `SkillRegistry.installedDirNames()`.
    func commandFiles(fileManager: FileManager = .default) -> [(url: URL, scope: CustomCommand.Scope)] {
        var out: [(url: URL, scope: CustomCommand.Scope)] = []
        for (root, scope) in [(userRoot, CustomCommand.Scope.user)]
            + (projectRoot.map { [($0, CustomCommand.Scope.project)] } ?? []) {
            let entries = (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? []
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where url.pathExtension.lowercased() == "md" {
                out.append((url, scope))
            }
        }
        return out
    }

    /// `~/Library/Application Support/<bundle-id>/Commands` (mirrors
    /// `SkillPaths.defaultRoot()`, but the `Commands` subdir).
    static func defaultUserRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Commands", isDirectory: true)
    }

    static func projectRoot(forWorkspace workspace: URL) -> URL {
        workspace.appendingPathComponent(".ainkrad", isDirectory: true)
            .appendingPathComponent("commands", isDirectory: true)
    }
}
