import Foundation

/// Loads, validates, and dedups the active skill set from disk. The markdown
/// files are the source of truth; `reload()` is idempotent and cheap. `_proposed`
/// is deliberately excluded from the active set until a draft is `approve(name:)`d
/// (Tasks 7-8 build the UI around this proposal workflow).
@MainActor
final class SkillRegistry {
    let paths: SkillPaths
    private let fm: FileManager
    private let marketplaceNames: () -> Set<String>

    private(set) var skills: [Skill] = []
    private(set) var loadErrors: [(name: String, message: String)] = []
    var onChange: (() -> Void)?

    init(paths: SkillPaths,
         fileManager: FileManager = .default,
         marketplaceNames: @escaping () -> Set<String> = { [] }) {
        self.paths = paths
        self.fm = fileManager
        self.marketplaceNames = marketplaceNames
        // Safe to call even when nothing exists yet; makes reload()'s
        // directory enumeration meaningful without a separate setup step.
        try? paths.ensureDirectoriesExist(fileManager: fileManager)
        reload()
    }

    func skill(named name: String) -> Skill? { skills.first { $0.name == name } }

    /// Re-scans `root`'s immediate subdirectories (excluding `_proposed`),
    /// parses + validates each `SKILL.md`, and rebuilds the active,
    /// deduped set. A malformed/invalid/unreadable skill is skipped and
    /// recorded in `loadErrors` — never fatal to the rest of the load.
    func reload() {
        var loaded: [String: Skill] = [:]     // keyed by skill.name
        var errors: [(name: String, message: String)] = []
        let mp = marketplaceNames()

        for dirName in installedDirNames() {
            let url = paths.skillFile(dirName)
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                errors.append((dirName, "unreadable or not valid UTF-8: \(error.localizedDescription)"))
                continue
            }

            let source: SkillSource = mp.contains(dirName) ? .marketplace : .local
            do {
                let skill = try SkillParser.parse(text, source: source)
                let issues = SkillValidator.validate(skill)
                guard issues.isEmpty else {
                    errors.append((dirName, "invalid: \(issues)"))
                    continue
                }
                if let existing = loaded[skill.name] {
                    // Local overrides marketplace on a name collision, regardless
                    // of directory enumeration order; otherwise first-seen wins
                    // (dirs are enumerated in sorted order for determinism).
                    if source == .local && existing.source != .local {
                        loaded[skill.name] = skill
                    }
                } else {
                    loaded[skill.name] = skill
                }
            } catch {
                errors.append((dirName, String(describing: error)))
            }
        }
        skills = loaded.values.sorted { $0.name < $1.name }
        loadErrors = errors
        onChange?()
    }

    /// Writes/overwrites an active local skill directly and reloads. Used by
    /// the manager's editor.
    func writeLocal(_ text: String, name: String) throws {
        let url = paths.skillFile(name)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        reload()
    }

    // MARK: - Proposal workflow (agent-drafted skills, pending approval)

    /// Writes a draft to `_proposed/<name>/SKILL.md`. Deliberately does NOT
    /// touch the active set — a proposed skill is inert until `approve(name:)`.
    func propose(_ text: String, name: String) throws {
        let url = paths.proposedFile(name)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Moves a proposal from `_proposed/<name>` into active `Skills/<name>`,
    /// then reloads so it takes effect (subject to the usual validation and
    /// dedup rules — approving an invalid draft still yields a captured
    /// `loadErrors` entry rather than crashing).
    func approve(name: String) throws {
        let source = paths.proposedFile(name)
        let destination = paths.skillFile(name)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: source, to: destination)
        // Clean up the now-empty proposal directory, if any.
        try? fm.removeItem(at: paths.proposedDir(name))
        reload()
    }

    /// Removes a pending proposal. Operates only on `_proposed/`; never
    /// touches the active set.
    func discard(name: String) throws {
        try fm.removeItem(at: paths.proposedDir(name))
    }

    /// Immediate subdirectories of `root`, excluding `_proposed`, sorted for
    /// deterministic dedup regardless of filesystem enumeration order.
    private func installedDirNames() -> [String] {
        guard let entries = try? fm.contentsOfDirectory(
            at: paths.root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.compactMap { url -> String? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = url.lastPathComponent
            guard isDir, name != "_proposed" else { return nil }
            return name
        }.sorted()
    }
}
