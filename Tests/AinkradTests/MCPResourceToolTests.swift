import Testing
import Foundation
import AinkradAppKit
@testable import Ainkrad
@testable import AinkradHostRuntime

@MainActor
@Suite("mcp_read_resource")
struct MCPResourceToolTests {
    func registry() -> MCPServerRegistry {
        let server = MCPAppServer(appID: "demo")
        server.addResource(.init(uri: "demo://buffer", title: "Buffer") { "live value" })
        let activator = AppServerActivator(
            servers: ["demo": server], isAppOpen: { _ in true },
            requestOpen: { _ in }, availability: { _ in .available })
        let configStore = MCPServerConfigStore(persistence: InMemoryPersistenceStore(),
                                               secrets: InMemorySecretStore())
        configStore.upsert(MCPServerConfig(
            id: "demo", displayName: "Demo", transport: .inProcess,
            enabled: true, trusted: false, appID: "demo"))
        return MCPServerRegistry(configStore: configStore, activator: activator)
    }

    @Test("reads a resource through the owning server", .timeLimit(.minutes(1)))
    func readsResource() async throws {
        let registry = registry()
        await registry.connectEnabled()
        let tool = MCPReadResourceTool(registry: registry)
        let result = try await tool.execute(.object([
            "server": .string("demo"), "uri": .string("demo://buffer"),
        ]))
        #expect(!result.isError)
        #expect(result.content == "live value")
    }

    @Test("is a read-class tool so it is gated like other reads")
    func isReadClass() {
        #expect(MCPReadResourceTool(registry: registry()).permission == .read)
    }

    @Test("an unknown server returns an error result, never a throw",
          .timeLimit(.minutes(1)))
    func unknownServerErrors() async throws {
        let tool = MCPReadResourceTool(registry: registry())   // never connected
        let result = try await tool.execute(.object([
            "server": .string("ghost"), "uri": .string("demo://buffer"),
        ]))
        #expect(result.isError)
        #expect(result.content.contains("ghost"))
    }
}
