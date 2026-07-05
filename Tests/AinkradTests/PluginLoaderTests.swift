import Testing
import Foundation
@testable import Ainkrad
@testable import AinkradAppKit

@MainActor
struct PluginLoaderTests {
    /// Writes a `.bundle` directory with a hand-authored Info.plist (no binary,
    /// so `Bundle.load()` fails after metadata passes — enough to exercise
    /// discovery, validation, and failure isolation without compiling code).
    private func writeBundle(in dir: URL, name: String, info: [String: Any]) throws {
        let bundle = dir.appendingPathComponent("\(name).bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Info.plist"))
    }

    private func loader(signaturePolicy: PluginSignaturePolicy = DevModeSignaturePolicy()) -> PluginLoader {
        PluginLoader(signaturePolicy: signaturePolicy) { appID in
            HostServicesImpl(
                appID: appID,
                dataRootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                secretStore: InMemorySecretStore(),
                themeManager: ThemeManager(persistence: InMemoryPersistenceStore())
            )
        }
    }

    private var validInfo: [String: Any] {
        [
            PluginInfoKey.appID: "hello",
            PluginInfoKey.displayName: "Hello",
            PluginInfoKey.iconSymbol: "hand.wave",
            PluginInfoKey.apiVersion: 1,
            PluginInfoKey.principalClass: "DoesNotExist",
            "CFBundleExecutable": "hello",
        ]
    }

    @Test("a bundle with an unsupported API version is skipped, not loaded")
    func rejectsBadAPIVersion() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info = validInfo
        info[PluginInfoKey.apiVersion] = 999
        try writeBundle(in: dir, name: "Future", info: info)

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("API version 999"))
    }

    @Test("a bundle missing a required key is skipped")
    func rejectsMissingKey() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info = validInfo
        info.removeValue(forKey: PluginInfoKey.appID)
        try writeBundle(in: dir, name: "NoID", info: info)

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("metadata"))
    }

    @Test("a valid-metadata bundle with no loadable binary fails at load, isolated")
    func loadFailureIsolated() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeBundle(in: dir, name: "Binaryless", info: validInfo)

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)   // recorded, no crash
    }

    @Test("a missing directory yields no apps and no failures")
    func missingDirectory() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let result = loader().loadAll(from: [missing])
        #expect(result.apps.isEmpty)
        #expect(result.failures.isEmpty)
    }

    @Test("a bundle with a path-traversal app id is skipped before load")
    func rejectsPathTraversalAppID() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info = validInfo
        info[PluginInfoKey.appID] = "../../escape"
        try writeBundle(in: dir, name: "Escape", info: info)

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("invalid app id"))
    }

    @Test("a valid-metadata bundle is skipped before load when the signature policy rejects it")
    func rejectsOnSignaturePolicy() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeBundle(in: dir, name: "Rejected", info: validInfo)

        let result = loader(signaturePolicy: DeveloperIDSignaturePolicy()).loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("signature:"))
    }

    @Test("one bad bundle does not suppress processing of its siblings")
    func multiBundleIsolation() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var badAPI = validInfo; badAPI[PluginInfoKey.apiVersion] = 999
        try writeBundle(in: dir, name: "Future", info: badAPI)          // rejected at validation
        var noID = validInfo; noID.removeValue(forKey: PluginInfoKey.appID)
        try writeBundle(in: dir, name: "NoID", info: noID)              // rejected at metadata parse

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 2)   // BOTH processed — the scan never aborts early
    }
}
