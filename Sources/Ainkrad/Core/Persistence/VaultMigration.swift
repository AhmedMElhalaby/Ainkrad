import Foundation
import AinkradAppKit

/// Moves pre-Home data into a vault using **copy → verify → mark**.
///
/// Never moves and never deletes user data: if anything fails part-way — including
/// a full disk mid-copy — the user's files are still exactly where they have always
/// been, and the caller has not yet written a pointer, so the next launch is a clean
/// first run. The only rename this performs is the final marker (`Documents` →
/// `Documents.migrated`, inside the legacy container), and it happens only after
/// every row has been copied and verified.
///
/// Secrets are not part of the legacy tree — they live in the Keychain and are
/// deliberately untouched here. Nothing in this type logs a file's contents.
///
/// This is the ONLY file in `Sources/` permitted to call `applicationSupportDirectory`:
/// locating the pre-Home tree is precisely its job.
enum VaultMigration {

    // MARK: - Report

    /// What happened to one row of the relocation table. Every row is always
    /// present in the report, including rows whose legacy source did not exist,
    /// so a caller can never mistake "absent" for "done".
    struct RowResult: Equatable {
        /// The row's legacy label, e.g. `"*.json"`, `"Plugins/"`, `"../Skills/"`.
        let row: String
        /// Absolute path of the destination the row maps to.
        let destination: String
        /// Whether the legacy source existed at all.
        let present: Bool
        /// Container-relative paths copied and byte-verified.
        let copied: [String]
        /// Container-relative paths left alone because the destination already existed.
        let skipped: [String]
    }

    struct Report: Equatable {
        /// Every path copied, across all rows. For the `*.json` row the entries are
        /// bare file names (`"agents.json"`); for directory rows they are prefixed
        /// with the legacy directory (`"PluginData/Lore/state.json"`).
        let copied: [String]
        /// Every path skipped because a destination file already existed.
        let skipped: [String]
        /// Row-by-row detail; one entry per relocation, in table order.
        let rows: [RowResult]
    }

    // MARK: - Locating the legacy tree

    /// `~/Library/Application Support/<bundle-id>`, the pre-Home container.
    static func legacyContainerURL() -> URL? {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    /// `~/Library/Application Support/<bundle-id>/Documents`, the pre-Home document root.
    static func legacyDocumentsURL() -> URL? {
        legacyContainerURL()?.appendingPathComponent("Documents", isDirectory: true)
    }

    /// True when the container holds pre-Home data that has not been marked yet.
    static func needsMigration(container: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: container.path) else { return false }
        // Already migrated: the Documents rename is the marker.
        if fm.fileExists(atPath: markerURL(container: container).path) { return false }
        return rows(container: container, home: Home(vaultRoot: container, cacheRoot: container))
            .contains { row in
                switch row.kind {
                case .jsonFiles:
                    let names = (try? fm.contentsOfDirectory(atPath: row.source.path)) ?? []
                    return names.contains { $0.hasSuffix(".json") }
                case .recursiveDirectory:
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: row.source.path, isDirectory: &isDir),
                          isDir.boolValue else { return false }
                    return !(((try? fm.contentsOfDirectory(atPath: row.source.path)) ?? []).isEmpty)
                }
            }
    }

    // MARK: - The relocation table

    private enum RowKind { case jsonFiles, recursiveDirectory }

    private struct Row {
        let label: String
        /// Prefix used for the container-relative names reported for this row.
        let reportPrefix: String
        let source: URL
        let destination: URL
        let kind: RowKind
    }

    /// The ten relocations Task 5 performed, in table order. Sources are resolved
    /// against the legacy `<bundle-id>` container: the first six live under its
    /// `Documents/`, the last four are siblings of `Documents/`.
    private static func rows(container: URL, home: Home) -> [Row] {
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        func doc(_ name: String) -> URL { documents.appendingPathComponent(name, isDirectory: true) }
        func sib(_ name: String) -> URL { container.appendingPathComponent(name, isDirectory: true) }
        let apps = home.vaultRoot.appendingPathComponent("Apps", isDirectory: true)

        return [
            Row(label: "*.json", reportPrefix: "",
                source: documents, destination: home.shared(.config), kind: .jsonFiles),
            Row(label: "Plugins/", reportPrefix: "Plugins",
                source: doc("Plugins"),
                destination: home.cacheRoot.appendingPathComponent("Plugins", isDirectory: true),
                kind: .recursiveDirectory),
            Row(label: "DevPlugins/", reportPrefix: "DevPlugins",
                source: doc("DevPlugins"),
                destination: home.cacheRoot.appendingPathComponent("DevPlugins", isDirectory: true),
                kind: .recursiveDirectory),
            Row(label: "PluginData/", reportPrefix: "PluginData",
                source: doc("PluginData"), destination: apps, kind: .recursiveDirectory),
            Row(label: "RetainedPluginData/", reportPrefix: "RetainedPluginData",
                source: doc("RetainedPluginData"),
                destination: apps.appendingPathComponent(".retained", isDirectory: true),
                kind: .recursiveDirectory),
            Row(label: "Sounds/", reportPrefix: "Sounds",
                source: doc("Sounds"), destination: home.shared(.sounds), kind: .recursiveDirectory),
            Row(label: "../Skills/", reportPrefix: "Skills",
                source: sib("Skills"), destination: home.shared(.skills), kind: .recursiveDirectory),
            Row(label: "../Memory/", reportPrefix: "Memory",
                source: sib("Memory"), destination: home.shared(.memory), kind: .recursiveDirectory),
            Row(label: "../Commands/", reportPrefix: "Commands",
                source: sib("Commands"), destination: home.shared(.commands),
                kind: .recursiveDirectory),
            Row(label: "../Shares/", reportPrefix: "Shares",
                source: sib("Shares"),
                destination: home.shared(.sessions)
                    .appendingPathComponent("shares", isDirectory: true),
                kind: .recursiveDirectory),
        ]
    }

    private static func markerURL(container: URL) -> URL {
        container.appendingPathComponent("Documents.migrated", isDirectory: true)
    }

    // MARK: - Migrate

    /// Copies every relocated path out of the legacy `<bundle-id>` container into
    /// `home`, verifies each copy byte-for-byte, then marks the legacy `Documents`
    /// directory as migrated.
    ///
    /// - Parameter legacy: the legacy `<bundle-id>` container — NOT its `Documents`
    ///   subdirectory, because four of the ten relocated paths are siblings of it.
    /// - Throws: on the first unverifiable or failed copy, leaving no marker.
    @discardableResult
    static func migrate(fromContainer legacy: URL, into home: Home) throws -> Report {
        let fm = FileManager.default
        var results: [RowResult] = []
        var anythingPresent = false

        for row in rows(container: legacy, home: home) {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: row.source.path, isDirectory: &isDir) && isDir.boolValue
            guard exists else {
                results.append(RowResult(row: row.label, destination: row.destination.path,
                                         present: false, copied: [], skipped: []))
                continue
            }

            let (copied, skipped): ([String], [String])
            switch row.kind {
            case .jsonFiles:
                (copied, skipped) = try migrateJSONFiles(from: row.source, to: row.destination)
            case .recursiveDirectory:
                (copied, skipped) = try migrateDirectory(
                    from: row.source, to: row.destination, prefix: row.reportPrefix)
            }
            // "Present" means the legacy source existed — even if every file in it
            // was skipped. Absent and skipped must stay distinguishable.
            anythingPresent = true
            results.append(RowResult(row: row.label, destination: row.destination.path,
                                     present: true, copied: copied, skipped: skipped))
        }

        // Mark last: only a fully verified migration gets marked, so a failure
        // anywhere above leaves the container looking exactly un-migrated.
        if anythingPresent {
            let documents = legacy.appendingPathComponent("Documents", isDirectory: true)
            let marked = markerURL(container: legacy)
            if fm.fileExists(atPath: documents.path), !fm.fileExists(atPath: marked.path) {
                try fm.moveItem(at: documents, to: marked)
            }
        }

        return Report(copied: results.flatMap(\.copied),
                      skipped: results.flatMap(\.skipped),
                      rows: results)
    }

    // MARK: - Row strategies

    /// The `*.json` row: top-level JSON documents only, non-recursive.
    private static func migrateJSONFiles(from source: URL, to destination: URL)
        throws -> ([String], [String]) {
        let fm = FileManager.default
        var copied: [String] = []
        var skipped: [String] = []
        let names = try fm.contentsOfDirectory(atPath: source.path).sorted()
            .filter { $0.hasSuffix(".json") }
        guard !names.isEmpty else { return ([], []) }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for name in names {
            let target = destination.appendingPathComponent(name)
            guard !fm.fileExists(atPath: target.path) else {
                skipped.append(name)
                continue
            }
            try copyVerified(from: source.appendingPathComponent(name), to: target)
            copied.append(name)
        }
        return (copied, skipped)
    }

    /// A directory row: recursive, file-by-file, so an existing destination file is
    /// skipped individually rather than the whole subtree being clobbered or refused.
    private static func migrateDirectory(from source: URL, to destination: URL, prefix: String)
        throws -> ([String], [String]) {
        let fm = FileManager.default
        var copied: [String] = []
        var skipped: [String] = []

        let sourcePath = source.standardizedFileURL.path
        guard let walker = fm.enumerator(at: source,
                                         includingPropertiesForKeys: [.isDirectoryKey],
                                         options: []) else {
            throw CocoaError(.fileReadUnknown)
        }
        var files: [(relative: String, url: URL)] = []
        var directories: [String] = []
        for case let item as URL in walker {
            let path = item.standardizedFileURL.path
            guard path.hasPrefix(sourcePath + "/") else { continue }
            let relative = String(path.dropFirst(sourcePath.count + 1))
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: path, isDirectory: &isDir)
            // A symlink resolving to a directory is still copied as a link, not walked.
            let isSymlink = (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?
                .isSymbolicLink ?? false
            if isDir.boolValue && !isSymlink {
                directories.append(relative)
            } else {
                files.append((relative, item))
            }
        }

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for relative in directories.sorted() {
            try fm.createDirectory(at: destination.appendingPathComponent(relative, isDirectory: true),
                                   withIntermediateDirectories: true)
        }

        for file in files.sorted(by: { $0.relative < $1.relative }) {
            let target = destination.appendingPathComponent(file.relative)
            let name = prefix.isEmpty ? file.relative : "\(prefix)/\(file.relative)"
            guard !fm.fileExists(atPath: target.path) else {
                skipped.append(name)
                continue
            }
            try copyVerified(from: file.url, to: target)
            copied.append(name)
        }

        // Directory-level verification: every source entry must now exist at the
        // destination — copied by us, or already there and deliberately skipped.
        for relative in directories where !fm.fileExists(
            atPath: destination.appendingPathComponent(relative, isDirectory: true).path) {
            throw CocoaError(.fileWriteUnknown)
        }
        for file in files where !fm.fileExists(
            atPath: destination.appendingPathComponent(file.relative).path) {
            throw CocoaError(.fileWriteUnknown)
        }
        return (copied, skipped)
    }

    // MARK: - Copy → verify

    /// Copies one file and verifies what landed against what was read. A short
    /// write — a full disk part-way through — is silent data loss otherwise, so a
    /// failed verification removes the partial destination and throws. The SOURCE
    /// is never touched.
    ///
    /// `verify` is injectable so a test can exercise the failure branch without
    /// filling a disk.
    static func copyVerified(from source: URL, to target: URL,
                             verify: (URL, URL) throws -> Bool = contentsMatch) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        do {
            try fm.copyItem(at: source, to: target)
        } catch {
            try? fm.removeItem(at: target)
            throw error
        }

        // Symlinks are copied as links; comparing the link targets, not the
        // (possibly absent) files they point at, is the only meaningful check.
        let isSymlink = (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]))?
            .isSymbolicLink ?? false
        if isSymlink {
            let a = try? fm.destinationOfSymbolicLink(atPath: source.path)
            let b = try? fm.destinationOfSymbolicLink(atPath: target.path)
            guard a != nil, a == b else {
                try? fm.removeItem(at: target)
                throw CocoaError(.fileWriteUnknown)
            }
            return
        }

        let matched: Bool
        do {
            matched = try verify(source, target)
        } catch {
            try? fm.removeItem(at: target)
            throw error
        }
        guard matched else {
            try? fm.removeItem(at: target)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Byte-for-byte comparison, streamed in chunks so a large plugin bundle is
    /// never held in memory twice.
    static func contentsMatch(_ a: URL, _ b: URL) throws -> Bool {
        let fm = FileManager.default
        let sizeA = (try fm.attributesOfItem(atPath: a.path)[.size] as? NSNumber)?.intValue
        let sizeB = (try fm.attributesOfItem(atPath: b.path)[.size] as? NSNumber)?.intValue
        guard sizeA == sizeB else { return false }

        let handleA = try FileHandle(forReadingFrom: a)
        defer { try? handleA.close() }
        let handleB = try FileHandle(forReadingFrom: b)
        defer { try? handleB.close() }

        let chunk = 1 << 20
        while true {
            let dataA = try handleA.read(upToCount: chunk) ?? Data()
            let dataB = try handleB.read(upToCount: chunk) ?? Data()
            guard dataA == dataB else { return false }
            if dataA.isEmpty { return true }
        }
    }
}
