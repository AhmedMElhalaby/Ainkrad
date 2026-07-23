import Foundation
import Observation
import AinkradAppKit
import AinkradHostRuntime

/// Drives the Dev Host's load-one-bundle contract: validate the bundle
/// through the SAME shared validation the real host and store review use,
/// then (only on a validation pass) load it in-process. Keeping validation
/// 100% real is what makes the Dev Host's rejection message match what a
/// developer would see from store review — see `AinkradHostRuntime.PluginValidator`.
@Observable
@MainActor
final class DevHostModel {
    enum State {
        case empty
        case invalid(String)
        case loaded(RegisteredApp)
    }

    private(set) var state: State = .empty

    /// The in-process load step, injected so this model's validation path can
    /// be exercised end-to-end in tests without a compiled plugin binary
    /// (mirrors `PluginInstaller`'s `loadBundle` seam) while the default in
    /// the running app performs a REAL load via `PluginLoader`.
    private let loadBundle: (URL) -> Result<RegisteredApp, PluginRejection>

    init(loadBundle: @escaping (URL) -> Result<RegisteredApp, PluginRejection>) {
        self.loadBundle = loadBundle
    }

    /// Builds the model the running app uses: real validation AND a real
    /// in-process load via `PluginLoader`, backed by dev-scoped in-memory
    /// host services (mirrors `PluginLoaderTests.stubHost`).
    convenience init() {
        self.init(loadBundle: { url in
            PluginLoader(signaturePolicy: DevModeSignaturePolicy()) { appID, declaredPresentation in
                DevHostModel.makeHostServices(appID: appID, presentation: declaredPresentation)
            }.loadBundle(at: url)
        })
    }

    private static func makeHostServices(appID: String, presentation: PluginPresentation) -> HostServices {
        HostServicesImpl(
            appID: appID,
            dataRootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AinkradDevHost", isDirectory: true),
            secretStore: InMemorySecretStore(),
            themeManager: ThemeManager(persistence: InMemoryPersistenceStore()),
            hub: AgentContextRegistryHub(),
            actionHub: AgentActionRegistryHub(),
            launchHub: PluginLaunchHub(),
            declaredPresentation: presentation,
            appAppearanceStore: AppAppearanceStore(persistence: InMemoryPersistenceStore())
        )
    }

    /// Validates `args.bundleURL` through the shared module, then loads it on
    /// a validation pass. `args.generation`, when set, overrides the
    /// otherwise-default `minSupportedAPIVersion == AinkradAppKit.apiVersion`
    /// floor — letting a developer pin the Dev Host to an older generation to
    /// exercise compatibility rejection locally.
    func load(_ args: LaunchArguments) {
        guard let bundle = Bundle(url: args.bundleURL), let info = bundle.infoDictionary else {
            state = .invalid("missing Info.plist")
            return
        }

        let metadata: PluginBundleMetadata
        switch PluginBundleMetadata.parse(infoDictionary: info) {
        case .success(let m):
            metadata = m
        case .failure(let error):
            state = .invalid("metadata: \(error)")
            return
        }

        let minSupportedAPIVersion = args.generation ?? AinkradAppKit.apiVersion
        if case .failure(let rejection) = PluginValidator.validate(
            metadata, infoDictionary: info, minSupportedAPIVersion: minSupportedAPIVersion) {
            state = .invalid(rejection.reason)
            return
        }

        switch loadBundle(args.bundleURL) {
        case .success(let app):
            state = .loaded(app)
        case .failure(let rejection):
            state = .invalid(rejection.reason)
        }
    }
}
