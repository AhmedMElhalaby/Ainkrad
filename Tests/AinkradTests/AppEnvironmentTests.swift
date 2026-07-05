import Testing
import Foundation
@testable import Ainkrad

@MainActor
private final class SpyDockIconUpdater: DockIconUpdating {
    func updateDockIcon(_ icon: AppIcon) {}
}

private struct NoOpCatalogSource: CatalogSource {
    func fetchCatalog() async throws -> [CatalogEntry] { [] }
}

@Suite("AppEnvironment")
final class AppEnvironmentTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ainkrad-tests-\(UUID().uuidString)")
    deinit { try? FileManager.default.removeItem(at: root) }

    @Test("exposes the exact dependencies it was constructed with")
    @MainActor
    func exposesInjectedDependencies() {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let registry = BuiltInAppRegistry(persistence: persistence)
        let themeManager = ThemeManager(persistence: persistence, dockIconUpdater: SpyDockIconUpdater())
        let workspaceManager = WorkspaceManager()
        let launcherStore = LauncherStore(registry: registry, workspaceManager: workspaceManager)
        let connectionStore = ConnectionStore(persistence: persistence, secrets: secrets)
        let catalogService = CatalogService(
            source: NoOpCatalogSource(), persistence: persistence)
        let installer = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: FileManager.default.temporaryDirectory.appendingPathComponent("plugins"),
            pluginDataDir: FileManager.default.temporaryDirectory.appendingPathComponent("plugin-data"),
            persistence: persistence, registry: registry, loadBundle: { _ in .failure(PluginRejection(reason: "x")) })
        let marketplace = MarketplaceService(catalog: catalogService, installer: installer, persistence: persistence)
        let marketplaceStore = MarketplaceStore(service: marketplace, registry: registry)

        let environment = AppEnvironment(
            persistence: persistence,
            secrets: secrets,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: launcherStore,
            connectionStore: connectionStore,
            marketplace: marketplace,
            marketplaceStore: marketplaceStore
        )

        #expect(environment.registry === registry)
        #expect(environment.themeManager === themeManager)
        #expect(environment.workspaceManager === workspaceManager)
        #expect(environment.launcherStore === launcherStore)
        #expect(environment.connectionStore === connectionStore)
        #expect(environment.marketplace === marketplace)
        #expect(environment.marketplaceStore === marketplaceStore)
    }

    @Test("bootstrap() assembles a working environment on isolated storage, Launcher dismissed")
    @MainActor
    func bootstrapAssemblesRealDependencies() {
        // Isolate the legacy-import source too: bootstrap runs
        // LegacyUserDefaultsMigration against `defaults`, so a shared
        // `.standard` would import stray real `com.ainkrad.app` state and
        // make these assertions non-hermetic on any machine/CI runner.
        let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment.bootstrap(rootURL: root, defaults: isolatedDefaults)
        #expect(environment.themeManager.currentTheme == .neonBlue)
        // Settings left the registry — it is now a summonable overlay, not a
        // tiled Block, so Terminal is the only registered app.
        #expect(environment.registry.allApps.map { $0.id } == ["terminal"])
        #expect(environment.workspaceManager.workspaces.count == 1)
        #expect(environment.isLauncherPresented == false)
        #expect(environment.isSettingsPresented == false)
    }
}
