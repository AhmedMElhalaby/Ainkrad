import Testing
import Foundation
@testable import Ainkrad

@MainActor
private final class SpyDockIconUpdater: DockIconUpdating {
    func updateDockIcon(for theme: Theme) {}
}

@Suite("AppEnvironment")
final class AppEnvironmentTests {
    let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { self.defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }

    @Test("exposes the exact dependencies it was constructed with")
    @MainActor
    func exposesInjectedDependencies() {
        let settingsStore = UserDefaultsSettingsStore(defaults: defaults)
        let registry = BuiltInAppRegistry(apps: [], settingsStore: settingsStore)
        let themeManager = ThemeManager(settingsStore: settingsStore, dockIconUpdater: SpyDockIconUpdater())
        let workspaceManager = WorkspaceManager()
        let launcherStore = LauncherStore(registry: registry, workspaceManager: workspaceManager)

        let environment = AppEnvironment(
            settingsStore: settingsStore,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: launcherStore
        )

        #expect(environment.registry === registry)
        #expect(environment.themeManager === themeManager)
        #expect(environment.workspaceManager === workspaceManager)
        #expect(environment.launcherStore === launcherStore)
    }

    @Test("bootstrap() assembles a working environment backed by real UserDefaults, Launcher dismissed")
    @MainActor
    func bootstrapAssemblesRealDependencies() {
        let environment = AppEnvironment.bootstrap(defaults: defaults)
        #expect(environment.themeManager.currentTheme == .neonBlue)
        #expect(environment.registry.allApps.map { $0.id } == ["terminal"])
        #expect(environment.workspaceManager.workspaces.count == 1)
        #expect(environment.isLauncherPresented == false)
    }
}
