import Foundation
import CryptoKit
import AinkradAppKit

enum MarketplaceError: Error, Equatable {
    case download(String)
    case checksumMismatch
    case unpack(String)
    case invalidBundle(String)
    case notInstalled(String)
    case notNewer
}

/// Installs / updates / uninstalls plugin bundles from catalog entries. All
/// filesystem effects are atomic: a bundle is fully validated in a temp
/// directory before it is moved into `pluginsDir`.
@MainActor
final class PluginInstaller {
    // `HTTPClient` is a plain (non-Sendable) protocol; conformers used here
    // (URLSessionHTTPClient, test stubs) are immutable value types, so a
    // stored `let` is safe to hand across the actor boundary for the await
    // (same pattern as `CatalogService.source`).
    private nonisolated(unsafe) let http: HTTPClient
    private let unzipper: Unzipper
    private let pluginsDir: URL
    private let pluginDataDir: URL
    private let persistence: PersistenceStore
    private let registry: BuiltInAppRegistry
    // `loadBundle` is a plain (non-Sendable) closure type; the only await in
    // `install` happens before it is used, so a stored `let` crossing the
    // actor boundary is safe (same pattern as `CatalogService.source`).
    private nonisolated(unsafe) let loadBundle: (URL) -> Result<RegisteredApp, PluginRejection>

    init(http: HTTPClient, unzipper: Unzipper, pluginsDir: URL, pluginDataDir: URL,
         persistence: PersistenceStore, registry: BuiltInAppRegistry,
         loadBundle: @escaping (URL) -> Result<RegisteredApp, PluginRejection>) {
        self.http = http; self.unzipper = unzipper
        self.pluginsDir = pluginsDir; self.pluginDataDir = pluginDataDir
        self.persistence = persistence; self.registry = registry; self.loadBundle = loadBundle
    }

    func install(_ entry: CatalogEntry) async throws {
        // 1. Download.
        let data: Data
        do { data = try await http.get(entry.downloadURL) }
        catch { throw MarketplaceError.download(String(describing: error)) }

        // 2. Verify integrity BEFORE unpacking.
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == entry.sha256.lowercased() else { throw MarketplaceError.checksumMismatch }

        // 3. Unpack into a temp dir.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        let zip = work.appendingPathComponent("dl.zip")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do { try data.write(to: zip); try unzipper.unzip(zip, to: work.appendingPathComponent("x")) }
        catch { throw MarketplaceError.unpack(String(describing: error)) }

        // 4. Locate the bundle root and validate it (metadata + appID matches
        //    entry). `DittoUnzipper` (used both here and by the tooling that
        //    creates archives, per `ditto -c -k <dir>`'s documented behavior)
        //    unzips a directory's CONTENTS, not the directory itself — so the
        //    extracted root normally IS the bundle (Contents/Info.plist sits
        //    directly under it). Fall back to a `.bundle`-suffixed child for
        //    archives that do wrap the bundle in a top-level folder.
        let unpacked = work.appendingPathComponent("x")
        func readMetadata(at url: URL) -> PluginBundleMetadata? {
            guard let info = Bundle(url: url)?.infoDictionary,
                  case .success(let m) = PluginBundleMetadata.parse(infoDictionary: info) else { return nil }
            return m
        }
        let bundleURL: URL
        let metadata: PluginBundleMetadata
        if let m = readMetadata(at: unpacked) {
            bundleURL = unpacked; metadata = m
        } else if let child = (try? FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "bundle" }), let m = readMetadata(at: child) {
            bundleURL = child; metadata = m
        } else {
            throw MarketplaceError.invalidBundle("no readable .bundle in archive")
        }
        guard metadata.appID == entry.appID else { throw MarketplaceError.invalidBundle("appID mismatch") }
        if case .failure(let rej) = PluginValidator.validate(metadata, minSupportedAPIVersion: 1) {
            throw MarketplaceError.invalidBundle(rej.reason)
        }

        // 5. Atomic move into place (replace any prior install).
        let dest = pluginsDir.appendingPathComponent("\(entry.appID).bundle")
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: bundleURL, to: dest)

        // 6. Record installed state.
        var doc = persistence.load(InstalledPluginsDocument.self) ?? InstalledPluginsDocument()
        doc.installed[entry.appID] = .init(version: entry.version, sourceRepo: entry.sourceRepo)
        persistence.save(doc)

        // 7. Register live (best-effort — install succeeds even if a relaunch is
        //    needed to load; the files + state are already committed).
        if case .success(let app) = loadBundle(dest) { registry.register(app) }
        else { Log.marketplace.error("Installed \(entry.appID, privacy: .public) but live-load failed; effective next launch") }
    }
}
