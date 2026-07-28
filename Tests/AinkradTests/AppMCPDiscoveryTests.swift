import Testing
import SwiftUI
import AinkradAppKit
@testable import Ainkrad
@testable import AinkradHostRuntime

@MainActor
@Suite("AppMCPDiscovery")
struct AppMCPDiscoveryTests {
    func app(_ id: String, name: String, mcp: Bool) -> RegisteredApp {
        var app = RegisteredApp(
            id: id, displayName: name, icon: "circle",
            isEnabledByDefault: true, source: .builtIn,
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil })
        if mcp { app.mcpServerFactory = { MCPAppServer(appID: id) } }
        return app
    }

    func store() -> MCPServerConfigStore {
        MCPServerConfigStore(persistence: InMemoryPersistenceStore(),
                             secrets: InMemorySecretStore())
    }

    @Test("only apps publishing a server get a config")
    func synthesizesConfigsForMCPApps() {
        let configStore = store()
        AppMCPDiscovery.refresh(
            apps: [app("gitmage", name: "Git Mage", mcp: true),
                   app("notes", name: "Notes", mcp: false)],
            into: configStore)
        #expect(configStore.all().map(\.id) == ["gitmage"])
        let config = configStore.all()[0]
        #expect(config.transport == .inProcess)
        #expect(config.appID == "gitmage")
        #expect(config.displayName == "Git Mage")
        #expect(config.enabled)          // enabled by default
        #expect(!config.trusted)         // but gated by default
    }

    @Test("a second run preserves the user's enabled and trusted choices")
    func refreshPreservesUserChoices() throws {
        let configStore = store()
        let apps = [app("gitmage", name: "Git Mage", mcp: true)]
        AppMCPDiscovery.refresh(apps: apps, into: configStore)
        configStore.setEnabled(false, for: "gitmage")
        configStore.setTrusted(true, for: "gitmage")

        AppMCPDiscovery.refresh(apps: apps, into: configStore)
        let config = try #require(configStore.config(id: "gitmage"))
        #expect(!config.enabled)
        #expect(config.trusted)
    }

    @Test("an external server's config is left untouched")
    func leavesExternalConfigsAlone() throws {
        let configStore = store()
        configStore.upsert(MCPServerConfig(
            id: "brave", displayName: "Brave", transport: .stdio,
            command: "/usr/bin/brave", enabled: true, trusted: true))
        AppMCPDiscovery.refresh(apps: [app("gitmage", name: "Git Mage", mcp: true)],
                                into: configStore)
        let brave = try #require(configStore.config(id: "brave"))
        #expect(brave.transport == .stdio)
        #expect(brave.trusted)
        #expect(configStore.all().count == 2)
    }
}
