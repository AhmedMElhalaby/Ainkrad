// Sources/Ainkrad/Core/AgentKit/MCP/MCPServerRegistry.swift
import Foundation
import Observation

/// Connection/health state for one configured MCP server.
enum MCPHealth: Equatable {
    case connected(toolCount: Int)
    case needsConfiguration
    case failed(String)
    case disabled
}

/// Owns the live MCP connections: reads configs from `MCPServerConfigStore`, opens
/// `MCPClient` connections over the right transport for each enabled server, tracks
/// per-server enabled/trust state (delegated to the config store, the single source of
/// truth), exposes discovered tools, and tracks health/connection status.
///
/// One bad server can never break the registry: `connectEnabled()` handles each config
/// independently inside its own do/catch, so a failing connect/listTools for server A
/// only marks A `.failed` and moves on — server B still connects and is still queryable.
@MainActor
@Observable
final class MCPServerRegistry {
    private let configStore: MCPServerConfigStore
    private let clientFactory: @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore) -> MCPClient?
    private var clients: [String: MCPClient] = [:]
    private var tools: [String: [MCPToolDescriptor]] = [:]
    private(set) var health: [String: MCPHealth] = [:]

    /// - Parameter clientFactory: builds the right transport-backed client from a config.
    ///   Injectable so tests pass a stub-backed client and never spawn a real process or
    ///   hit the network.
    init(configStore: MCPServerConfigStore,
         clientFactory: @escaping @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore) -> MCPClient? =
            MCPServerRegistry.defaultClientFactory) {
        self.configStore = configStore
        self.clientFactory = clientFactory
    }

    /// Builds a real transport-backed client from a config. A config missing the field
    /// its transport requires (no `command` for stdio, no `url` for httpSSE) yields `nil`
    /// rather than crashing — `connectEnabled()` records that as `.failed`.
    @MainActor
    static func defaultClientFactory(_ config: MCPServerConfig,
                                      _ store: MCPServerConfigStore) -> MCPClient? {
        switch config.transport {
        case .stdio:
            guard let command = config.command else { return nil }
            let transport = StdioTransport(command: command, args: config.args,
                                            env: store.resolvedEnv(for: config.id))
            return MCPClient(transport: transport)
        case .httpSSE:
            guard let url = config.url else { return nil }
            let transport = HTTPSSETransport(endpoint: url,
                                              authHeaders: store.resolvedHeaders(for: config.id))
            return MCPClient(transport: transport)
        }
    }

    /// Connects every enabled server with no missing secrets and records health.
    /// Bounded/non-hanging: `MCPClient.connect()`/`listTools()` requests already carry
    /// their own timeout, so this introduces no additional unbounded await.
    func connectEnabled() async {
        for config in configStore.all() {
            guard config.enabled else { health[config.id] = .disabled; continue }
            guard configStore.missingSecrets(for: config.id).isEmpty else {
                health[config.id] = .needsConfiguration
                continue
            }
            guard let client = clientFactory(config, configStore) else {
                health[config.id] = .failed("invalid configuration")
                continue
            }
            do {
                try await client.connect()
                let discovered = try await client.listTools()
                clients[config.id] = client
                tools[config.id] = discovered
                health[config.id] = .connected(toolCount: discovered.count)
            } catch {
                health[config.id] = .failed(String(describing: error))
                await client.disconnect()
            }
        }
    }

    /// Disconnects every currently-connected client.
    func disconnectAll() async {
        for client in clients.values { await client.disconnect() }
        clients.removeAll()
        tools.removeAll()
    }

    /// Enabled+connected servers' discovered tools, keyed by owning server.
    func discoveredTools() -> [(server: String, descriptor: MCPToolDescriptor)] {
        tools.flatMap { server, descriptors in descriptors.map { (server: server, descriptor: $0) } }
    }

    func client(for server: String) -> MCPClient? {
        clients[server]
    }

    /// `mcp/<server>/<tool>` is trusted iff its owning server is enabled AND trusted.
    func isToolTrusted(_ namespacedName: String) -> Bool {
        let parts = namespacedName.split(separator: "/", maxSplits: 2)
        guard parts.count == 3, parts[0] == "mcp" else { return false }
        guard let config = configStore.config(id: String(parts[1])) else { return false }
        return config.enabled && config.trusted
    }
}
