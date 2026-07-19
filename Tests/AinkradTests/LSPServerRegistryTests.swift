// Tests/AinkradTests/LSPServerRegistryTests.swift
import Foundation
import Testing
@testable import Ainkrad

/// Transport whose `start()` always throws — used to make a server's handshake fail
/// deterministically (no dependence on timing/timeouts). Mirrors
/// `MCPServerRegistryTests.FailingStartTransport`.
private actor FailingStartTransport: MCPTransport {
    func start() async throws { throw MCPError.transport("boom") }
    func send(_ message: JSONValue) async throws {}
    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stop() async {}
}

@Suite("LSPServerRegistry")
@MainActor
struct LSPServerRegistryTests {
    /// A transport that answers `initialize` successfully with empty capabilities.
    private func workingTransport() -> StubMCPTransport {
        StubMCPTransport { message in
            guard let id = message["id"]?.stringValue else { return [] }
            return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                "result": .object(["capabilities": .object([:])])])]
        }
    }

    private func seeded(_ doc: LSPServersDocument) -> PersistenceStore {
        let p = InMemoryPersistenceStore(); p.save(doc); return p
    }

    @Test func matchesLanguageByGlob() {
        let doc = LSPServersDocument(servers: [
            LSPServerConfig(id: "swift", command: "sourcekit-lsp", args: [],
                            fileGlobs: ["*.swift"], enabled: true)])
        let registry = LSPServerRegistry(persistence: seeded(doc))
        #expect(registry.language(forFilePath: "/x/File.swift") == "swift")
        #expect(registry.language(forFilePath: "/x/File.rs") == nil)
    }

    @Test func disabledServersDoNotMatch() {
        let doc = LSPServersDocument(servers: [
            LSPServerConfig(id: "swift", command: "sourcekit-lsp", args: [],
                            fileGlobs: ["*.swift"], enabled: false)])
        let registry = LSPServerRegistry(persistence: seeded(doc))
        #expect(registry.language(forFilePath: "/x/File.swift") == nil)
    }

    @Test func noConfiguredServerReturnsNilClientGracefully() async {
        let registry = LSPServerRegistry(persistence: InMemoryPersistenceStore())
        let client = await registry.client(forFilePath: "/x/File.swift", rootURI: "file:///x")
        #expect(client == nil)
    }

    @Test func reusesOneClientPerLanguageAndWorkspaceRoot() async {
        let doc = LSPServersDocument(servers: [
            LSPServerConfig(id: "swift", command: "sourcekit-lsp", args: [],
                            fileGlobs: ["*.swift"], enabled: true)])
        var spawnCount = 0
        let registry = LSPServerRegistry(persistence: seeded(doc)) { [self] _ in
            spawnCount += 1
            return LSPClient(transport: workingTransport())
        }

        let first = await registry.client(forFilePath: "/x/A.swift", rootURI: "file:///root")
        let second = await registry.client(forFilePath: "/x/B.swift", rootURI: "file:///root")
        #expect(first != nil)
        #expect(second != nil)
        #expect(spawnCount == 1, "same language+root must reuse one client, not spawn a second")

        // A different workspace root for the same language gets its own client.
        let thirdRootSpawnCountBefore = spawnCount
        let third = await registry.client(forFilePath: "/x/A.swift", rootURI: "file:///other-root")
        #expect(third != nil)
        #expect(spawnCount == thirdRootSpawnCountBefore + 1)
    }

    @Test func aFailedStartIsMarkedUnhealthyButOthersStillWork() async {
        let doc = LSPServersDocument(servers: [
            LSPServerConfig(id: "bad", command: "bad-lsp", args: [], fileGlobs: ["*.bad"], enabled: true),
            LSPServerConfig(id: "good", command: "good-lsp", args: [], fileGlobs: ["*.good"], enabled: true),
        ])
        let registry = LSPServerRegistry(persistence: seeded(doc)) { [self] config in
            if config.id == "bad" {
                return LSPClient(transport: FailingStartTransport())
            }
            return LSPClient(transport: workingTransport())
        }

        let bad = await registry.client(forFilePath: "/x/f.bad", rootURI: "file:///root")
        let good = await registry.client(forFilePath: "/x/f.good", rootURI: "file:///root")

        #expect(bad == nil)
        #expect(good != nil)
        if case .failed = registry.health["bad::file:///root"] {
            // expected
        } else {
            Issue.record("expected 'bad' to be marked failed, got \(String(describing: registry.health["bad::file:///root"]))")
        }
        #expect(registry.health["good::file:///root"] == .connected)
    }

    @Test func configWithNoResolvableCommandYieldsNilClientWithoutThrowing() async {
        // Mirrors what autodetect() produces when nothing is found: no config at all for
        // that language, OR (here) a config whose command is empty because the default
        // client factory refuses to spawn an empty path.
        let doc = LSPServersDocument(servers: [
            LSPServerConfig(id: "swift", command: "", args: [], fileGlobs: ["*.swift"], enabled: true)])
        let registry = LSPServerRegistry(persistence: seeded(doc))
        let client = await registry.client(forFilePath: "/x/File.swift", rootURI: "file:///root")
        #expect(client == nil)
    }

    @Test func autodetectReturnsConfigsOnlyForResolvedBinaries() {
        let configs = LSPServerRegistry.autodetect { binary in
            switch binary {
            case "sourcekit-lsp": return "/usr/bin/sourcekit-lsp"
            case "gopls": return "/opt/homebrew/bin/gopls"
            default: return nil
            }
        }
        let ids = Set(configs.map(\.id))
        #expect(ids == ["swift", "go"])
        #expect(configs.allSatisfy { $0.enabled })
        #expect(configs.first { $0.id == "swift" }?.command == "/usr/bin/sourcekit-lsp")
        #expect(configs.first { $0.id == "swift" }?.fileGlobs == ["*.swift"])
    }

    @Test func autodetectFindsNothingWhenResolverAlwaysFails() {
        let configs = LSPServerRegistry.autodetect { _ in nil }
        #expect(configs.isEmpty)
    }

    @Test func lspServerConfigDecodesForwardCompatiblyWithDefaults() throws {
        // Payload missing every key but the required `id` (as an older/newer schema
        // might produce) must decode without throwing, using safe defaults.
        let json = #"{"id": "swift"}"#.data(using: .utf8)!
        let config = try PersistenceCoding.decoder.decode(LSPServerConfig.self, from: json)
        #expect(config.id == "swift")
        #expect(config.command == "")
        #expect(config.args == [])
        #expect(config.fileGlobs == [])
        #expect(config.enabled == true)
    }
}
