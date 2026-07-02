import Testing
import Foundation
import SwiftUI
@testable import Ainkrad

private struct StubTerminalApp: BuiltInApp {
    static let id = "terminal"
    static let displayName = "Terminal"
    static let icon = "terminal"
    static let isEnabledByDefault = true
    static func makeRootView() -> AnyView { AnyView(Text("Terminal")) }
    static func makeSettingsView() -> AnyView { AnyView(Text("Terminal Settings")) }
}

private struct StubSettingsApp: BuiltInApp {
    static let id = "settings"
    static let displayName = "Settings"
    static let icon = "gearshape"
    static let isEnabledByDefault = true
    static func makeRootView() -> AnyView { AnyView(Text("Settings")) }
    static func makeSettingsView() -> AnyView { AnyView(Text("Settings Settings")) }
}

@Suite("LauncherStore")
final class LauncherStoreTests {
    let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { self.defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }

    @MainActor
    private func makeStore() -> (LauncherStore, BuiltInAppRegistry, WorkspaceManager) {
        let registry = BuiltInAppRegistry(
            apps: [StubTerminalApp.self, StubSettingsApp.self],
            settingsStore: UserDefaultsSettingsStore(defaults: defaults)
        )
        let workspaceManager = WorkspaceManager()
        let store = LauncherStore(registry: registry, workspaceManager: workspaceManager)
        return (store, registry, workspaceManager)
    }

    @Test("with no query, appResults lists every enabled app")
    @MainActor
    func appResultsListsEnabledApps() {
        let (store, registry, _) = makeStore()
        registry.setEnabled(false, for: "settings")

        #expect(store.appResults.map { $0.id } == ["terminal"])
    }

    @Test("typing fuzzy-filters appResults")
    @MainActor
    func appResultsFuzzyFilters() {
        let (store, _, _) = makeStore()
        store.query = "trm"
        #expect(store.appResults.map { $0.id } == ["terminal"])
    }

    @Test("selectApp opens the app in the active workspace's tile layout")
    @MainActor
    func selectAppOpensBlockInActiveWorkspace() {
        let (store, _, workspaceManager) = makeStore()

        store.selectApp(StubTerminalApp.self)

        #expect(!workspaceManager.activeWorkspace.tileLayout.isEmpty)
    }
}
