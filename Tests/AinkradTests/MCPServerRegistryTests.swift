// Tests/AinkradTests/MCPServerRegistryTests.swift
import Foundation
import Testing
@testable import Ainkrad

/// Transport whose `start()` always throws — used to make a server's connect fail
/// deterministically (no dependence on timing/timeouts).
private actor FailingStartTransport: MCPTransport {
    func start() async throws { throw MCPError.transport("boom") }
    func send(_ message: JSONValue) async throws {}
    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stop() async {}
}

@Suite("MCPServerRegistry")
@MainActor
struct MCPServerRegistryTests {
    private func stubClientFactory() -> @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore) -> MCPClient? {
        return { _, _ in
            MCPClient(transport: StubMCPTransport { message in
                guard let id = message["id"]?.stringValue,
                      let method = message["method"]?.stringValue else { return [] }
                switch method {
                case "initialize":
                    return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object(["capabilities": .object([:])])])]
                case "tools/list":
                    return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object(["tools": .array([
                            .object(["name": .string("search"),
                                     "inputSchema": .object(["type": .string("object")])])])])])]
                default:
                    return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object([:])])]
                }
            })
        }
    }

    private func registry() -> (MCPServerRegistry, MCPServerConfigStore) {
        let configs = MCPServerConfigStore(persistence: InMemoryPersistenceStore(),
                                           secrets: InMemorySecretStore())
        return (MCPServerRegistry(configStore: configs, clientFactory: stubClientFactory()), configs)
    }

    @Test func connectsEnabledServerAndDiscoversTools() async {
        let (registry, configs) = registry()
        configs.upsert(MCPServerConfig(id: "srv", displayName: "S", transport: .stdio,
                                       command: "x", enabled: true, trusted: false))
        await registry.connectEnabled()
        #expect(registry.health["srv"] == .connected(toolCount: 1))
        let tools = registry.discoveredTools()
        #expect(tools.map(\.descriptor.name) == ["search"])
    }

    @Test func disabledServerContributesNoTools() async {
        let (registry, configs) = registry()
        configs.upsert(MCPServerConfig(id: "srv", displayName: "S", transport: .stdio,
                                       command: "x", enabled: false))
        await registry.connectEnabled()
        #expect(registry.discoveredTools().isEmpty)
        #expect(registry.health["srv"] == .disabled)
    }

    @Test func serverWithMissingSecretNeedsConfiguration() async {
        let (registry, configs) = registry()
        configs.upsert(MCPServerConfig(id: "srv", displayName: "S", transport: .stdio,
                                       command: "x", envKeys: ["KEY"], enabled: true))
        await registry.connectEnabled()
        #expect(registry.health["srv"] == .needsConfiguration)
        #expect(registry.discoveredTools().isEmpty)
    }

    @Test func trustFollowsEnabledAndTrustedFlags() async {
        let (registry, configs) = registry()
        configs.upsert(MCPServerConfig(id: "srv", displayName: "S", transport: .stdio,
                                       command: "x", enabled: true, trusted: true))
        await registry.connectEnabled()
        #expect(registry.isToolTrusted("mcp/srv/search"))
        #expect(!registry.isToolTrusted("mcp/other/x"))
        #expect(!registry.isToolTrusted("read_file"))
    }

    @Test func oneFailingServerDoesNotBreakOthers() async {
        // "bad" gets a client whose transport always fails to start; "good" gets the
        // normal working stub. Deterministic (no reliance on the factory returning nil
        // or on timing): proves one server's connect failure can't stop another from
        // succeeding.
        let configs = MCPServerConfigStore(persistence: InMemoryPersistenceStore(),
                                           secrets: InMemorySecretStore())
        let workingFactory = stubClientFactory()
        let factory: @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore) -> MCPClient? = { config, store in
            if config.id == "bad" {
                return MCPClient(transport: FailingStartTransport())
            }
            return workingFactory(config, store)
        }
        let registry = MCPServerRegistry(configStore: configs, clientFactory: factory)
        configs.upsert(MCPServerConfig(id: "bad", displayName: "Bad", transport: .stdio,
                                       command: "x", enabled: true))
        configs.upsert(MCPServerConfig(id: "good", displayName: "Good", transport: .stdio,
                                       command: "x", enabled: true))
        await registry.connectEnabled()
        if case .failed = registry.health["bad"] {
            // expected: a server whose transport fails to start surfaces as failed
        } else {
            Issue.record("expected 'bad' server to be marked failed, got \(String(describing: registry.health["bad"]))")
        }
        #expect(registry.health["good"] == .connected(toolCount: 1))
        #expect(registry.discoveredTools().map(\.descriptor.name) == ["search"])
    }

    @Test func enabledAndTrustedTogglesPersistViaConfigStore() async {
        let (registry, configs) = registry()
        configs.upsert(MCPServerConfig(id: "srv", displayName: "S", transport: .stdio,
                                       command: "x", enabled: false, trusted: false))
        configs.setEnabled(true, for: "srv")
        configs.setTrusted(true, for: "srv")
        #expect(configs.config(id: "srv")?.enabled == true)
        #expect(configs.config(id: "srv")?.trusted == true)
        await registry.connectEnabled()
        #expect(registry.health["srv"] == .connected(toolCount: 1))
        #expect(registry.isToolTrusted("mcp/srv/search"))
        _ = registry
    }
}
