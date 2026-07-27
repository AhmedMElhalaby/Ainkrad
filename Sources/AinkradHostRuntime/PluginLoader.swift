import SwiftUI
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
        // Generation 8: teardown is discovered by CAST, never required. A
        // generation-7 bundle fails this cast and is simply left alone — which
        // is the whole point of adding capability this way rather than as a new
        // protocol requirement (an added requirement has no witness in an
        // already-compiled bundle, and the bundle stops loading entirely).
        var teardown: (@MainActor () -> Void)?
        if let teardownable = appType as? AinkradAppTeardown.Type,
           let identified = host as? PluginInstanceIdentity {
            let instance = identified.instanceID
            teardown = { teardownable.teardown(instance: instance) }
        }
        return .success(.plugin(appType, url: url, apiVersion: metadata.apiVersion, host: host,
                                presentation: metadata.presentation, teardown: teardown))
    }
}

extension RegisteredApp {
    /// Adapts a dynamically-loaded `AinkradApp` type, binding it to its scoped
    /// host services. Plugins are enabled by default; the registry override
    /// still applies.
    @MainActor
    public static func plugin(_ app: any AinkradApp.Type, url: URL, apiVersion: Int, host: HostServices,
                              presentation: PluginPresentation,
                              teardown: (@MainActor () -> Void)? = nil) -> RegisteredApp {
        var registered = RegisteredApp(
            id: app.id,
            displayName: app.displayName,
            icon: app.icon,
            isEnabledByDefault: true,
            source: .plugin(url: url, apiVersion: apiVersion),
            // Generation 8: ONE theme delivery path.
            //
            // `HostServices.theme` and the SDK's `@Entry` environment keys were
            // disjoint mechanisms carrying the same data — a plugin could read
            // either, they were injected from different places, and nothing
            // guaranteed they agreed. The environment wins (it is what every
            // `AinkradAppKit` component already reads, and it is per-view, so a
            // preview or a nested surface can override it). `HostServices.theme`
            // is now the *injection point*: the host feeds the environment from
            // it here, so a plugin's own scoped theme is authoritative for its
            // subtree rather than whatever the host root happened to publish.
            //
            // Read inside the closure so `HostTheme`'s `@Observable` tokens stay
            // live — a theme change re-renders the plugin, as before.
            makeRootView: { AnyView(app.makeRootView(host: host).ainkradHostTheme(host.theme)) },
            makeSettingsView: { AnyView(app.makeSettingsView(host: host).ainkradHostTheme(host.theme)) },
            chromeFill: { app.chromeFill(host: host) },
            presentation: presentation
        )
        registered.teardown = teardown
        return registered
    }
}
