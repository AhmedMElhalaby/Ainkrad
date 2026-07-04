import Testing
import SwiftUI
@testable import Ainkrad

@MainActor
struct RegisteredAppRegistryTests {
    private func app(_ id: String, enabledByDefault: Bool = true) -> RegisteredApp {
        RegisteredApp(
            id: id, displayName: id.capitalized, icon: "app",
            isEnabledByDefault: enabledByDefault, source: .builtIn,
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil }
        )
    }

    @Test("installed apps are exposed via allApps")
    func exposesInstalled() {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [app("terminal")])
        #expect(registry.allApps.map(\.id) == ["terminal"])
    }

    @Test("default-enabled state comes from the app when no override exists")
    func defaultEnabled() {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [app("a"), app("b", enabledByDefault: false)])
        #expect(registry.enabledApps.map(\.id) == ["a"])
    }

    @Test("an override flips and persists enabled state")
    func overridePersists() {
        let store = InMemoryPersistenceStore()
        let registry = BuiltInAppRegistry(persistence: store)
        registry.install(builtIn: [app("a")])
        registry.setEnabled(false, for: "a")
        #expect(registry.enabledApps.isEmpty)

        let reloaded = BuiltInAppRegistry(persistence: store)
        reloaded.install(builtIn: [app("a")])
        #expect(reloaded.enabledApps.isEmpty)
    }
}
