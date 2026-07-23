import Foundation
import AinkradAppKit
// Scoped import: the host's own `@main` struct is named `AinkradHostApp`
// (`App/AinkradApp.swift`), so this scoped import binds the bare name
// `AinkradApp` to the SDK protocol.
import protocol AinkradAppKit.AinkradApp

/// Discovers `.bundle`s in the given directories and turns the loadable ones
/// into `RegisteredApp`s. Every failure is isolated: it is logged, recorded,
/// and skipped — the host always finishes loading whatever it can.
@MainActor
public final class PluginLoader {
    private let signaturePolicy: PluginSignaturePolicy
    private let minSupportedAPIVersion: Int
    private let makeHostServices: (String, PluginPresentation) -> HostServices

    public init(signaturePolicy: PluginSignaturePolicy,
         minSupportedAPIVersion: Int = GenerationSupport.minSupported,
         makeHostServices: @escaping (String, PluginPresentation) -> HostServices) {
        self.signaturePolicy = signaturePolicy
        self.minSupportedAPIVersion = minSupportedAPIVersion
        self.makeHostServices = makeHostServices
    }

    public func loadAll(from directories: [URL]) -> (apps: [RegisteredApp], failures: [PluginLoadFailure]) {
        var apps: [RegisteredApp] = []
        var failures: [PluginLoadFailure] = []
        for dir in directories {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in entries where url.pathExtension == "bundle" {
                switch loadBundle(at: url) {
                case .success(let app):
                    apps.append(app)
                case .failure(let rejection):
                    failures.append(PluginLoadFailure(url: url, reason: rejection.reason))
                    Log.registry.error("Skipped plugin \(url.lastPathComponent, privacy: .public): \(rejection.reason, privacy: .public)")
                }
            }
        }
        // Dedup by appID, keeping the LAST directory's bundle — so a sideloaded
        // `DevPlugins` build overrides an installed release of the same app in
        // `Plugins` (directories are passed [Plugins, DevPlugins], dev last).
        // Without this both load and the registry keeps the installed one,
        // shadowing the dev build. In production there is no `DevPlugins`, so
        // this is a no-op.
        var byID: [String: RegisteredApp] = [:]
        var order: [String] = []
        for app in apps {
            if byID[app.id] == nil { order.append(app.id) }
            byID[app.id] = app
        }
        let deduped = order.compactMap { byID[$0] }
        return (deduped, failures)
    }

    /// Loads and validates a single bundle into a `RegisteredApp`. Public so the
    /// installer can register a freshly-installed bundle without a relaunch.
    public func loadBundle(at url: URL) -> Result<RegisteredApp, PluginRejection> {
        guard let bundle = Bundle(url: url) else { return .failure(PluginRejection(reason: "not a bundle")) }
        guard let info = bundle.infoDictionary else { return .failure(PluginRejection(reason: "missing Info.plist")) }

        let metadata: PluginBundleMetadata
        switch PluginBundleMetadata.parse(infoDictionary: info) {
        case .success(let m): metadata = m
        case .failure(let e): return .failure(PluginRejection(reason: "metadata: \(e)"))
        }

        if case .failure(let rejection) = PluginValidator.validate(metadata, infoDictionary: info, minSupportedAPIVersion: minSupportedAPIVersion) {
            return .failure(rejection)
        }

        if case .failure(let rejection) = signaturePolicy.validate(bundleURL: url) {
            return .failure(PluginRejection(reason: "signature: \(rejection.reason)"))
        }

        guard bundle.load() else { return .failure(PluginRejection(reason: "Bundle.load() failed")) }
        guard let principal = bundle.principalClass as? AinkradPluginEntryPoint.Type else {
            return .failure(PluginRejection(reason: "principal class missing or not AinkradPluginEntryPoint"))
        }

        // This is the one line that runs third-party plugin code in-process:
        // a `fatalError` (or other crash) inside plugin code here will crash
        // loading. Inherent to in-process loading — isolating it would need a
        // subprocess/XPC boundary, out of scope here.
        let appType = principal.app()
        let host = makeHostServices(metadata.appID, metadata.presentation)
        return .success(.plugin(appType, url: url, apiVersion: metadata.apiVersion, host: host, presentation: metadata.presentation))
    }
}

extension RegisteredApp {
    /// Adapts a dynamically-loaded `AinkradApp` type, binding it to its scoped
    /// host services. Plugins are enabled by default; the registry override
    /// still applies.
    @MainActor
    public static func plugin(_ app: any AinkradApp.Type, url: URL, apiVersion: Int, host: HostServices, presentation: PluginPresentation) -> RegisteredApp {
        RegisteredApp(
            id: app.id,
            displayName: app.displayName,
            icon: app.icon,
            isEnabledByDefault: true,
            source: .plugin(url: url, apiVersion: apiVersion),
            makeRootView: { app.makeRootView(host: host) },
            makeSettingsView: { app.makeSettingsView(host: host) },
            chromeFill: { app.chromeFill(host: host) },
            presentation: presentation
        )
    }
}
