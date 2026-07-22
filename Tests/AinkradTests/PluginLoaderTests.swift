import Testing
import Foundation
import SwiftUI
@testable import Ainkrad
@testable import AinkradAppKit

/// A minimal `AinkradApp` conformance for exercising `RegisteredApp.plugin(...)`
/// directly (the loader's fixtures are binary-less, so the factory is never
/// reached end-to-end in unit tests).
private enum StubApp: AinkradApp {
    static let id = "stub"
    static let displayName = "Stub"
    static let icon = "app"
    static func makeRootView(host: HostServices) -> AnyView { AnyView(EmptyView()) }
    static func makeSettingsView(host: HostServices) -> AnyView { AnyView(EmptyView()) }
}

@MainActor
struct PluginLoaderTests {
    /// The in-memory `HostServices` the `loader()` closure builds, reused by the
    /// factory test. `declaredPresentation` here is irrelevant to what the
    /// factory test asserts (that test guards the factory's own `presentation:`
    /// argument, not the host's).
    private func stubHost(appID: String, presentation: PluginPresentation = .pane) -> HostServices {
        HostServicesImpl(
            appID: appID,
            dataRootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
            secretStore: InMemorySecretStore(),
            themeManager: ThemeManager(persistence: InMemoryPersistenceStore()),
            hub: AgentContextRegistryHub(),
            actionHub: AgentActionRegistryHub(),
            launchHub: PluginLaunchHub(),
            declaredPresentation: presentation,
            appAppearanceStore: AppAppearanceStore(persistence: InMemoryPersistenceStore())
        )
    }

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
        PluginLoader(signaturePolicy: signaturePolicy) { appID, declaredPresentation in
            self.stubHost(appID: appID, presentation: declaredPresentation)
        }
    }

    private var validInfo: [String: Any] {
        [
            PluginInfoKey.appID: "hello",
            PluginInfoKey.displayName: "Hello",
            PluginInfoKey.iconSymbol: "hand.wave",
            PluginInfoKey.apiVersion: 7,
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
        #expect(result.failures[0].reason.contains("999"))
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

    /// Guards the value both open paths (tiling and overlay) read: the
    /// `presentation:` argument passed to `RegisteredApp.plugin(...)` must land
    /// in `RegisteredApp.presentation`. (The loader's own binary-less fixtures
    /// never reach this factory, so this is asserted directly.)
    @Test("the plugin factory propagates the declared presentation into RegisteredApp")
    func pluginFactoryPropagatesDeclaredPresentation() {
        let url = URL(fileURLWithPath: "/tmp/x")
        let overlay = RegisteredApp.plugin(
            StubApp.self, url: url, apiVersion: 4, host: stubHost(appID: "stub"), presentation: .overlay)
        #expect(overlay.presentation == .overlay)

        let pane = RegisteredApp.plugin(
            StubApp.self, url: url, apiVersion: 4, host: stubHost(appID: "stub"), presentation: .pane)
        #expect(pane.presentation == .pane)
    }
}
