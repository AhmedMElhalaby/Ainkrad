import Foundation
import AinkradAppKit
// Scoped import: the host's own `@main` struct is also named `AinkradApp`
// (`App/AinkradApp.swift`), so a wildcard `import AinkradAppKit` alone leaves
// the bare name `AinkradApp` pointing at the host struct, not the SDK
// protocol. This scoped import binds it to the SDK protocol instead.
import protocol AinkradAppKit.AinkradApp

/// Discovers `.bundle`s in the given directories and turns the loadable ones
/// into `RegisteredApp`s. Every failure is isolated: it is logged, recorded,
/// and skipped — the host always finishes loading whatever it can.
@MainActor
final class PluginLoader {
    private let signaturePolicy: PluginSignaturePolicy
    private let minSupportedAPIVersion: Int
    private let makeHostServices: (String) -> HostServices

    init(signaturePolicy: PluginSignaturePolicy,
         minSupportedAPIVersion: Int = 1,
         makeHostServices: @escaping (String) -> HostServices) {
        self.signaturePolicy = signaturePolicy
        self.minSupportedAPIVersion = minSupportedAPIVersion
        self.makeHostServices = makeHostServices
    }

    func loadAll(from directories: [URL]) -> (apps: [RegisteredApp], failures: [PluginLoadFailure]) {
        var apps: [RegisteredApp] = []
        var failures: [PluginLoadFailure] = []
        for dir in directories {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in entries where url.pathExtension == "bundle" {
                switch load(url: url) {
                case .success(let app):
                    apps.append(app)
                case .failure(let reason):
                    failures.append(PluginLoadFailure(url: url, reason: reason))
                    Log.registry.error("Skipped plugin \(url.lastPathComponent, privacy: .public): \(reason, privacy: .public)")
                }
            }
        }
        return (apps, failures)
    }

    private func load(url: URL) -> Result<RegisteredApp, String> {
        guard let bundle = Bundle(url: url) else { return .failure("not a bundle") }
        guard let info = bundle.infoDictionary else { return .failure("missing Info.plist") }

        let metadata: PluginBundleMetadata
        switch PluginBundleMetadata.parse(infoDictionary: info) {
        case .success(let m): metadata = m
        case .failure(let e): return .failure("metadata: \(e)")
        }

        guard AinkradAppKit.isCompatible(bundleAPIVersion: metadata.apiVersion,
                                         minSupported: minSupportedAPIVersion,
                                         current: AinkradAppKit.apiVersion) else {
            return .failure("API version \(metadata.apiVersion) unsupported")
        }

        if case .failure(let reason) = signaturePolicy.validate(bundleURL: url) {
            return .failure("signature: \(reason)")
        }

        guard bundle.load() else { return .failure("Bundle.load() failed") }
        guard let principal = bundle.principalClass as? AinkradPluginEntryPoint.Type else {
            return .failure("principal class missing or not AinkradPluginEntryPoint")
        }

        let appType = principal.app()
        let host = makeHostServices(metadata.appID)
        return .success(.plugin(appType, url: url, apiVersion: metadata.apiVersion, host: host))
    }
}

extension RegisteredApp {
    /// Adapts a dynamically-loaded `AinkradApp` type, binding it to its scoped
    /// host services. Plugins are enabled by default; the registry override
    /// still applies.
    @MainActor
    static func plugin(_ app: any AinkradApp.Type, url: URL, apiVersion: Int, host: HostServices) -> RegisteredApp {
        RegisteredApp(
            id: app.id,
            displayName: app.displayName,
            icon: app.icon,
            isEnabledByDefault: true,
            source: .plugin(url: url, apiVersion: apiVersion),
            makeRootView: { app.makeRootView(host: host) },
            makeSettingsView: { app.makeSettingsView(host: host) },
            chromeFill: { app.chromeFill(host: host) }
        )
    }
}
