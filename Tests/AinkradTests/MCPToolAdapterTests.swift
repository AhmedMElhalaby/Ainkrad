// Tests/AinkradTests/MCPToolAdapterTests.swift
import Foundation
import Testing
@testable import Ainkrad

@Suite("MCPToolAdapter")
@MainActor
struct MCPToolAdapterTests {
    private func client() -> MCPClient {
        MCPClient(transport: StubMCPTransport { message in
            guard let id = message["id"]?.stringValue,
                  let method = message["method"]?.stringValue else { return [] }
            switch method {
            case "initialize":
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                    "result": .object(["capabilities": .object([:])])])]
            case "tools/call":
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                    "result": .object(["content": .array([
                        .object(["type": .string("text"), "text": .string("hi from mcp")])])])])]
            default:
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                    "result": .object([:])])]
            }
        })
    }

    /// A client whose `tools/call` always answers with `isError: true` — used to
    /// prove a server-reported tool failure surfaces as a typed `ToolResult`
    /// (isError: true) rather than throwing out of `execute`.
    private func erroringClient() -> MCPClient {
        MCPClient(transport: StubMCPTransport { message in
            guard let id = message["id"]?.stringValue,
                  let method = message["method"]?.stringValue else { return [] }
            switch method {
            case "initialize":
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                    "result": .object(["capabilities": .object([:])])])]
            case "tools/call":
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                    "result": .object(["isError": .bool(true), "content": .array([
                        .object(["type": .string("text"), "text": .string("boom")])])])])]
            default:
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id),
                    "result": .object([:])])]
            }
        })
    }

    @Test func namespacesAndForwardsSchema() {
        let desc = MCPToolDescriptor(name: "search", description: "web search",
                                     inputSchema: .object(["type": .string("object")]))
        let adapter = MCPToolAdapter(server: "web", descriptor: desc, client: client())
        #expect(adapter.name == "mcp/web/search")
        #expect(adapter.description == "web search")
        #expect(adapter.permission == .write)
        #expect(adapter.parametersSchema["type"]?.stringValue == "object")
    }

    @Test func executeRoutesToClient() async throws {
        let c = client()
        try await c.connect()
        let desc = MCPToolDescriptor(name: "search", description: "", inputSchema: .object([:]))
        let adapter = MCPToolAdapter(server: "web", descriptor: desc, client: c)
        let r = try await adapter.execute(.object(["q": .string("swift")]))
        #expect(!r.isError)
        #expect(r.content == "hi from mcp")
    }

    @Test func serverToolErrorSurfacesAsNonCrashingResult() async throws {
        let c = erroringClient()
        try await c.connect()
        let desc = MCPToolDescriptor(name: "search", description: "", inputSchema: .object([:]))
        let adapter = MCPToolAdapter(server: "web", descriptor: desc, client: c)
        let r = try await adapter.execute(.object([:]))
        #expect(r.isError)
        #expect(r.content.contains("boom"))
    }

    @Test func namespaceParsesBackToServerAndTool() {
        let desc = MCPToolDescriptor(name: "search", description: "", inputSchema: .object([:]))
        let adapter = MCPToolAdapter(server: "web", descriptor: desc, client: client())
        let parts = adapter.name.split(separator: "/", maxSplits: 2)
        #expect(parts.count == 3)
        #expect(parts[0] == "mcp")
        #expect(String(parts[1]) == "web")
        #expect(String(parts[2]) == "search")
    }
}
