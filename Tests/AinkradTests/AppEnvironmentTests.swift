import Testing
import Foundation
@testable import Ainkrad

@MainActor
private final class SpyDockIconUpdater: DockIconUpdating {
    func updateDockIcon(_ icon: AppIcon) {}
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
        let registry = BuiltInAppRegistry(apps: [], persistence: persistence)
        let themeManager = ThemeManager(persistence: persistence, dockIconUpdater: SpyDockIconUpdater())
        let workspaceManager = WorkspaceManager()
        let launcherStore = LauncherStore(registry: registry, workspaceManager: workspaceManager)
        let terminalSettingsStore = TerminalSettingsStore(persistence: persistence)

        let environment = AppEnvironment(
            persistence: persistence,
            secrets: secrets,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: launcherStore,
            terminalSettingsStore: terminalSettingsStore
        )

        #expect(environment.registry === registry)
        #expect(environment.themeManager === themeManager)
        #expect(environment.workspaceManager === workspaceManager)
        #expect(environment.launcherStore === launcherStore)
        #expect(environment.terminalSettingsStore === terminalSettingsStore)
    }

    @Test("bootstrap() assembles a working environment backed by real UserDefaults, Launcher dismissed")
    @MainActor
    func bootstrapAssemblesRealDependencies() {
        let environment = AppEnvironment.bootstrap(rootURL: root)
        #expect(environment.themeManager.currentTheme == .neonBlue)
        // Settings left the registry — it is now a summonable overlay, not a
        // tiled Block, so Terminal is the only registered app.
        #expect(environment.registry.allApps.map { $0.id } == ["terminal"])
        #expect(environment.workspaceManager.workspaces.count == 1)
        #expect(environment.isLauncherPresented == false)
        #expect(environment.isSettingsPresented == false)
    }
}
