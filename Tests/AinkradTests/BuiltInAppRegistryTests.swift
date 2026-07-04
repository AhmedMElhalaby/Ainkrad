import Testing
import Foundation
import SwiftUI
@testable import Ainkrad

/// Stub conforming type — proves the protocol compiles against a real
/// conformance, per AIN-25's acceptance criterion.
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
    static let isEnabledByDefault = false
    static func makeRootView() -> AnyView { AnyView(Text("Settings")) }
    static func makeSettingsView() -> AnyView { AnyView(Text("Settings Settings")) }
}

@Suite("BuiltInAppRegistry")
final class BuiltInAppRegistryTests {
    let store = InMemoryPersistenceStore()

    private func makeRegistry() -> BuiltInAppRegistry {
        BuiltInAppRegistry(
            apps: [StubTerminalApp.self, StubSettingsApp.self],
            persistence: store
        )
    }

    @Test("exposes all registered apps in order")
    func exposesAllRegisteredApps() {
        let registry = makeRegistry()
        #expect(registry.allApps.map { $0.id } == ["terminal", "settings"])
    }

    @Test("enabledApps reflects each app's default-enabled flag before any toggle")
    func defaultEnabledState() {
        let registry = makeRegistry()
        #expect(registry.isEnabled("terminal") == true)
        #expect(registry.isEnabled("settings") == false)
        #expect(registry.enabledApps.map { $0.id } == ["terminal"])
    }

    @Test("toggling enabled state updates in-memory state immediately")
    func togglingUpdatesInMemory() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "terminal")
        #expect(registry.isEnabled("terminal") == false)
        #expect(registry.enabledApps.isEmpty)
    }

    @Test("enabled state survives a simulated relaunch (fresh registry, same store)")
    func enabledStatePersists() {
        let firstLaunch = makeRegistry()
        firstLaunch.setEnabled(false, for: "terminal")
        firstLaunch.setEnabled(true, for: "settings")

        let secondLaunch = BuiltInAppRegistry(
            apps: [StubTerminalApp.self, StubSettingsApp.self],
            persistence: store
        )

        #expect(secondLaunch.isEnabled("terminal") == false)
        #expect(secondLaunch.isEnabled("settings") == true)
    }
}
