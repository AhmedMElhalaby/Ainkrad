import Testing
import Foundation
import CryptoKit
import SwiftUI
@testable import Ainkrad
@testable import AinkradAppKit
import AinkradHostRuntime

/// Verifies `PluginInstaller.install` runs the SAME `StorePolicy` the store
/// review / CLI use, so "passes review" is defined by one shared authority
/// rather than the installer's own ad-hoc checks.
@MainActor
struct PluginInstallerStorePolicyTests {
    // Build a real .bundle dir (Info.plist only) and zip it with ditto; return
    // (zipURL, sha256Hex). Mirrors `PluginInstallerTests.makeBundleZip`.
    private func makeBundleZip(appID: String, api: Int = 7, dir: URL) throws -> (URL, String) {
        let bundle = dir.appendingPathComponent("\(appID).bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "AinkradAppID": appID, "AinkradDisplayName": appID, "AinkradIconSymbol": "app",
            "AinkradAPIVersion": api, "NSPrincipalClass": "X", "CFBundleExecutable": appID]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Info.plist"))
        let zip = dir.appendingPathComponent("\(appID).bundle.zip")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", dir.appendingPathComponent("\(appID).bundle").path, zip.path]
        try p.run(); p.waitUntilExit()
        let hash = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        return (zip, hash)
    }

    private func makeInstaller(http: HTTPClient, root: URL, registry: BuiltInAppRegistry) -> PluginInstaller {
        PluginInstaller(
            http: http, unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: InMemoryPersistenceStore(), registry: registry,
            loadBundle: { url in
                .success(RegisteredApp(id: url.deletingPathExtension().lastPathComponent, displayName: "x",
                    icon: "app", isEnabledByDefault: true, source: .plugin(url: url, apiVersion: 1),
                    makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })) })
    }

    @Test("a catalog entry missing a required store field (author) is rejected with StorePolicy's message")
    func missingAuthorRejected() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore()); registry.install(builtIn: [])
        let installer = makeInstaller(http: http, root: root, registry: registry)

        // Catalog entry has no author — StorePolicy must reject at intake.
        let entry = CatalogEntry(appID: "hello", displayName: "hello", icon: "app", description: "A helpful plugin.",
                                 version: "1.0.0", apiVersion: 1, downloadURL: url, sha256: sha, sourceRepo: "o/hello",
                                 author: nil)

        // Same info dict the installer parses from the real unpacked bundle
        // (built by `makeBundleZip` above), so the base-validation layer of
        // `StorePolicy.check` passes and the FIRST surfaced issue is the
        // missing-author check under test.
        let info: [String: Any] = [
            "AinkradAppID": "hello", "AinkradDisplayName": "hello", "AinkradIconSymbol": "app",
            "AinkradAPIVersion": 7, "NSPrincipalClass": "X", "CFBundleExecutable": "hello"]
        let expectedMessage = StorePolicy.check(
            manifest: StoreManifestInput(
                metadata: try PluginBundleMetadata.parse(infoDictionary: info).get(),
                infoDictionary: info, author: nil, description: "A helpful plugin.", iconSymbol: "app",
                declaredSHA256: sha, computedSHA256: sha),
            minSupported: GenerationSupport.minSupported, current: GenerationSupport.current
        ).first?.message

        await #expect(throws: AppStoreError.invalidBundle(expectedMessage ?? "")) {
            try await installer.install(entry)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/hello.bundle").path))
        #expect(registry.allApps.isEmpty)
    }

    @Test("a valid first-party bundle carrying author/description/icon still installs")
    func validFirstPartyBundleInstalls() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore()); registry.install(builtIn: [])
        let installer = makeInstaller(http: http, root: root, registry: registry)

        let entry = CatalogEntry(appID: "hello", displayName: "hello", icon: "app", description: "A helpful plugin.",
                                 version: "1.0.0", apiVersion: 1, downloadURL: url, sha256: sha, sourceRepo: "o/hello",
                                 author: "Ainkrad")

        try await installer.install(entry)

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/hello.bundle").path))
        #expect(registry.allApps.map(\.id) == ["hello"])
    }
}
