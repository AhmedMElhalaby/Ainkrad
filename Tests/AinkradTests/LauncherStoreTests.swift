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
    @MainActor
    private func makeStore() -> (LauncherStore, BuiltInAppRegistry, WorkspaceManager) {
        let registry = BuiltInAppRegistry(
            apps: [StubTerminalApp.self, StubSettingsApp.self],
            persistence: InMemoryPersistenceStore()
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

    @Test("selectApp from the main workspace creates a new workspace and opens the app there")
    @MainActor
    func selectAppFromMainCreatesNewWorkspace() {
        let (store, _, workspaceManager) = makeStore()
        let main = workspaceManager.activeWorkspace
        #expect(main.isMain)

        store.selectApp(StubTerminalApp.self)

        #expect(workspaceManager.workspaces.count == 2)
        #expect(main.tileLayout.isEmpty)
        #expect(!workspaceManager.activeWorkspace.isMain)
        #expect(workspaceManager.activeWorkspace.tileLayout.appIDs == ["terminal"])
    }

    @Test("selectApp on a non-main workspace splits into the current layout")
    @MainActor
    func selectAppOnNonMainSplitsInPlace() {
        let (store, _, workspaceManager) = makeStore()
        let mission = workspaceManager.createWorkspace()

        store.selectApp(StubTerminalApp.self)
        store.selectApp(StubSettingsApp.self)

        #expect(workspaceManager.workspaces.count == 2)
        #expect(workspaceManager.activeWorkspace.id == mission.id)
        #expect(mission.tileLayout.appIDs == ["terminal", "settings"])
    }
}
