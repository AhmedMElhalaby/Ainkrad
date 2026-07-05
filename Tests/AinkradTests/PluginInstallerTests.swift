import Testing
import Foundation
import CryptoKit
import SwiftUI
@testable import Ainkrad
@testable import AinkradAppKit

@MainActor
struct PluginInstallerTests {
    // Build a real .bundle dir (Info.plist only) and zip it with ditto; return
    // (zipURL, sha256Hex).
    private func makeBundleZip(appID: String, api: Int = 1, dir: URL) throws -> (URL, String) {
        let bundle = dir.appendingPathComponent("\(appID).bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "AinkradAppID": appID, "AinkradDisplayName": appID, "AinkradIconSymbol": "app",
            "AinkradAPIVersion": api, "NSPrincipalClass": "X"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Info.plist"))
        let zip = dir.appendingPathComponent("\(appID).bundle.zip")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", dir.appendingPathComponent("\(appID).bundle").path, zip.path]
        try p.run(); p.waitUntilExit()
        let hash = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        return (zip, hash)
    }

    private func entry(appID: String, url: URL, sha: String, version: String = "1.0.0") -> CatalogEntry {
        CatalogEntry(appID: appID, displayName: appID, icon: "app", description: "", version: version,
                     apiVersion: 1, downloadURL: url, sha256: sha, sourceRepo: "o/\(appID)")
    }

    private func makeInstaller(http: HTTPClient, root: URL, registry: BuiltInAppRegistry,
                               loadOK: Bool = true) -> PluginInstaller {
        PluginInstaller(
            http: http, unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: InMemoryPersistenceStore(), registry: registry,
            loadBundle: { url in
                loadOK
                ? .success(RegisteredApp(id: url.deletingPathExtension().lastPathComponent, displayName: "x",
                    icon: "app", isEnabledByDefault: true, source: .plugin(url: url, apiVersion: 1),
                    makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil }))
                : .failure(PluginRejection(reason: "load failed")) })
    }

    @Test("install places the bundle and registers it")
    func installHappy() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [])
        let installer = makeInstaller(http: http, root: root, registry: registry)
        try await installer.install(entry(appID: "hello", url: url, sha: sha))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/hello.bundle").path))
        #expect(registry.allApps.map(\.id) == ["hello"])
    }

    @Test("sha256 mismatch rejects and writes nothing")
    func checksumMismatch() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, _) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore()); registry.install(builtIn: [])
        let installer = makeInstaller(http: http, root: root, registry: registry)
        await #expect(throws: MarketplaceError.checksumMismatch) {
            try await installer.install(entry(appID: "hello", url: url, sha: "deadbeef"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/hello.bundle").path))
        #expect(registry.allApps.isEmpty)
    }

    @Test("a bundle whose appID differs from the catalog entry is rejected")
    func appIDMismatch() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "actual", dir: src)
        let url = URL(string: "https://e/x.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore()); registry.install(builtIn: [])
        let installer = makeInstaller(http: http, root: root, registry: registry)
        await #expect(throws: (any Error).self) {
            try await installer.install(entry(appID: "claimed", url: url, sha: sha))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/claimed.bundle").path))
    }

    @Test("version comparison is numeric per dot-segment")
    func versionCompare() {
        #expect(PluginVersion.isNewer("1.0.1", than: "1.0.0"))
        #expect(PluginVersion.isNewer("1.2", than: "1.1.9"))
        #expect(PluginVersion.isNewer("2.0", than: "1.9.9"))
        #expect(!PluginVersion.isNewer("1.0.0", than: "1.0.0"))
        #expect(!PluginVersion.isNewer("1.0.0", than: "1.0.1"))
    }

    @Test("update replaces on a newer version and refuses same/older")
    func update() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let store = InMemoryPersistenceStore()
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore()); registry.install(builtIn: [])
        let installer = PluginInstaller(http: http, unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"), pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: store, registry: registry,
            loadBundle: { u in .success(RegisteredApp(id: "hello", displayName: "x", icon: "app",
                isEnabledByDefault: true, source: .plugin(url: u, apiVersion: 1),
                makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })) })
        try await installer.install(entry(appID: "hello", url: url, sha: sha, version: "1.0.0"))
        await #expect(throws: MarketplaceError.notNewer) {
            try await installer.update(entry(appID: "hello", url: url, sha: sha, version: "1.0.0"))
        }
        try await installer.update(entry(appID: "hello", url: url, sha: sha, version: "1.1.0"))
        #expect(store.load(InstalledPluginsDocument.self)?.installed["hello"]?.version == "1.1.0")
    }

    @Test("uninstall removes files, state, and deregisters")
    func uninstall() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let store = InMemoryPersistenceStore()
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore()); registry.install(builtIn: [])
        let installer = PluginInstaller(http: http, unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"), pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: store, registry: registry,
            loadBundle: { u in .success(RegisteredApp(id: "hello", displayName: "x", icon: "app",
                isEnabledByDefault: true, source: .plugin(url: u, apiVersion: 1),
                makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })) })
        try await installer.install(entry(appID: "hello", url: url, sha: sha))
        try installer.uninstall(appID: "hello")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/hello.bundle").path))
        #expect(store.load(InstalledPluginsDocument.self)?.installed["hello"] == nil)
        #expect(registry.allApps.isEmpty)
    }
}

@MainActor
struct PluginInstallerRetentionTests {
    private func installer(root: URL) -> PluginInstaller {
        PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: InMemoryPersistenceStore(),
            registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            loadBundle: { _ in .failure(PluginRejection(reason: "unused")) })
    }

    @Test("uninstall moves scoped data to the retained area")
    func uninstallRetains() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let persistence = InMemoryPersistenceStore()
        var doc = InstalledPluginsDocument(); doc.installed["notes"] = .init(version: "1.0.0", sourceRepo: "o/notes"); persistence.save(doc)
        let inst = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: persistence, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            loadBundle: { _ in .failure(PluginRejection(reason: "unused")) })
        let live = root.appendingPathComponent("PluginData/notes")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: live.appendingPathComponent("settings.bin"))

        try inst.uninstall(appID: "notes")

        #expect(!FileManager.default.fileExists(atPath: live.path))                                  // live gone
        let retained = root.appendingPathComponent("RetainedPluginData/notes/settings.bin")
        #expect(FileManager.default.fileExists(atPath: retained.path))                               // retained present
        #expect((try? Data(contentsOf: retained)) == Data("hello".utf8))                             // data intact
        #expect(inst.hasRetainedData(appID: "notes") == true)
    }

    @Test("restore moves retained data back to live; discard deletes it")
    func restoreAndDiscard() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let inst = installer(root: root)
        let retained = root.appendingPathComponent("RetainedPluginData/notes")
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: retained.appendingPathComponent("settings.bin"))

        inst.restoreRetainedData(appID: "notes")
        #expect(!inst.hasRetainedData(appID: "notes"))
        #expect((try? Data(contentsOf: root.appendingPathComponent("PluginData/notes/settings.bin"))) == Data("keep".utf8))

        // now seed again and discard
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: retained.appendingPathComponent("settings.bin"))
        #expect(inst.hasRetainedData(appID: "notes"))
        inst.discardRetainedData(appID: "notes")
        #expect(!inst.hasRetainedData(appID: "notes"))
    }

    @Test("uninstall with no scoped data does not crash and retains nothing")
    func uninstallNoData() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let persistence = InMemoryPersistenceStore()
        var doc = InstalledPluginsDocument(); doc.installed["notes"] = .init(version: "1.0.0", sourceRepo: "o/notes"); persistence.save(doc)
        let inst = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: persistence, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            loadBundle: { _ in .failure(PluginRejection(reason: "unused")) })
        try inst.uninstall(appID: "notes")
        #expect(inst.hasRetainedData(appID: "notes") == false)
    }

    @Test("a second uninstall replaces the stale retained copy")
    func uninstallReplacesStale() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let persistence = InMemoryPersistenceStore()
        let inst = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: persistence, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            loadBundle: { _ in .failure(PluginRejection(reason: "unused")) })
        let live = root.appendingPathComponent("PluginData/notes")
        func writeLive(_ s: String) throws {
            try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
            try Data(s.utf8).write(to: live.appendingPathComponent("settings.bin"))
        }
        func markInstalled() { var d = InstalledPluginsDocument(); d.installed["notes"] = .init(version: "1", sourceRepo: "o"); persistence.save(d) }

        markInstalled(); try writeLive("first"); try inst.uninstall(appID: "notes")
        markInstalled(); try writeLive("second"); try inst.uninstall(appID: "notes")

        let retained = root.appendingPathComponent("RetainedPluginData/notes/settings.bin")
        #expect((try? Data(contentsOf: retained)) == Data("second".utf8))
    }
}
