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

    // MARK: - Description discovery

    /// A registry whose "demo" app publishes `count` resources, so the cap and
    /// overflow copy can be driven past `maxListedResources`.
    func registry(resourceCount count: Int) -> MCPServerRegistry {
        let server = MCPAppServer(appID: "demo")
        for i in 0..<count {
            // Zero-padded so lexical order matches numeric order, letting the
            // overflow assertions name an exact resource.
            server.addResource(.init(uri: String(format: "demo://r%03d", i),
                                     title: "Resource \(i)") { "v" })
        }
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

    @Test("the description enumerates a connected resource's server, uri and title",
          .timeLimit(.minutes(1)))
    func descriptionListsResources() async {
        let registry = registry()
        await registry.connectEnabled()
        let description = MCPReadResourceTool(registry: registry).description
        #expect(description.contains("demo://buffer"))
        #expect(description.contains("\"demo\""))
        #expect(description.contains("Buffer"))
    }

    @Test("the listing never displaces the truncated-context guidance",
          .timeLimit(.minutes(1)))
    func descriptionKeepsGuidance() async {
        let registry = registry()
        await registry.connectEnabled()
        let description = MCPReadResourceTool(registry: registry).description
        #expect(description.contains("truncated value and you need all of it"))
        // Guidance leads; the listing is an appendix, not the headline.
        #expect(description.hasPrefix(MCPReadResourceTool.guidance))
    }

    @Test("with no resources the description is the guidance alone, not an empty template")
    func descriptionDegradesWhenEmpty() {
        // Never connected, so nothing was ever discovered.
        let description = MCPReadResourceTool(registry: registry()).description
        #expect(description == MCPReadResourceTool.guidance)
        #expect(!description.contains("Currently available resources"))
    }

    @Test("the listing is capped and states how many it omitted",
          .timeLimit(.minutes(1)))
    func descriptionRespectsCap() async {
        let cap = MCPReadResourceTool.maxListedResources
        let registry = registry(resourceCount: cap + 5)
        await registry.connectEnabled()
        let description = MCPReadResourceTool(registry: registry).description

        // Exactly `cap` resource bullets, plus one overflow line.
        let listed = description.split(separator: "\n").filter { $0.hasPrefix("- server ") }
        #expect(listed.count == cap)
        #expect(description.contains("5 more resources not listed"))
        // The cut is honest about WHICH it dropped: the last one is absent.
        #expect(!description.contains("demo://r\(String(format: "%03d", cap + 4))"))
    }

    @Test("the description is live: it changes when a resource appears",
          .timeLimit(.minutes(1)))
    func descriptionIsLiveNotCaptured() async {
        let registry = registry()
        // Constructed BEFORE any connection — the bug this pins is a stored
        // `let description` frozen at bootstrap, when nothing is connected yet.
        let tool = MCPReadResourceTool(registry: registry)
        let before = tool.description
        #expect(!before.contains("demo://buffer"))

        await registry.connectEnabled()
        let after = tool.description
        #expect(after != before)
        #expect(after.contains("demo://buffer"))

        // ...and back again when the server goes away.
        await registry.disconnectAll()
        #expect(tool.description == before)
    }
}
