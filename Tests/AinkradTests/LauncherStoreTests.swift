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

    @Test("with no query, workspaceResults lists the current workspace marked, then + New Workspace")
    @MainActor
    func workspaceResultsListsCurrentAndNewEntry() {
        let (store, _, workspaceManager) = makeStore()

        let results = store.workspaceResults
        #expect(results.count == 2)
        guard case .workspace(let workspace, let label, let isCurrent) = results[0] else {
            Issue.record("expected a workspace result first")
            return
        }
        #expect(workspace.id == workspaceManager.activeWorkspace.id)
        #expect(label == "Workspace 1")
        #expect(isCurrent)
        #expect(results[1].isNewWorkspace)
    }

    @Test("workspaceResults marks only the active workspace as current")
    @MainActor
    func workspaceResultsMarksOnlyActiveAsCurrent() {
        let (store, _, workspaceManager) = makeStore()
        workspaceManager.createWorkspace()

        let results = store.workspaceResults
        let workspaceEntries = results.compactMap { result -> Bool? in
            if case .workspace(_, _, let isCurrent) = result { return isCurrent }
            return nil
        }
        #expect(workspaceEntries == [false, true])
    }

    @Test("typing fuzzy-filters workspaceResults by label, including + New Workspace")
    @MainActor
    func workspaceResultsFuzzyFilters() {
        let (store, _, workspaceManager) = makeStore()
        workspaceManager.createWorkspace()

        store.query = "workspace 1"
        let filtered = store.workspaceResults
        #expect(filtered.count == 1)
        guard case .workspace(_, let label, _) = filtered[0] else {
            Issue.record("expected a workspace result")
            return
        }
        #expect(label == "Workspace 1")
    }

    @Test("selectApp opens the app in the active workspace's tile layout")
    @MainActor
    func selectAppOpensBlockInActiveWorkspace() {
        let (store, _, workspaceManager) = makeStore()

        store.selectApp(StubTerminalApp.self)

        #expect(!workspaceManager.activeWorkspace.tileLayout.isEmpty)
    }

    @Test("selectWorkspace switches the active workspace")
    @MainActor
    func selectWorkspaceSwitchesActive() {
        let (store, _, workspaceManager) = makeStore()
        let first = workspaceManager.activeWorkspace
        let second = workspaceManager.createWorkspace()
        workspaceManager.switchTo(first.id)

        store.selectWorkspace(second)

        #expect(workspaceManager.activeWorkspace.id == second.id)
    }

    @Test("selectNewWorkspace creates a workspace and switches to it")
    @MainActor
    func selectNewWorkspaceCreatesAndSwitches() {
        let (store, _, workspaceManager) = makeStore()
        let originalCount = workspaceManager.workspaces.count

        store.selectNewWorkspace()

        #expect(workspaceManager.workspaces.count == originalCount + 1)
        #expect(workspaceManager.activeWorkspace.id == workspaceManager.workspaces.last?.id)
    }
}
