// Sources/Ainkrad/Core/AgentKit/MCP/MCPReadResourceTool.swift
import Foundation
import AinkradHostRuntime

/// Reads one MCP resource on demand.
///
/// Ambient app state still arrives every turn through `AgentContextRegistryHub`
/// → `<workspace_context>`; this tool is the pull-based complement for payloads
/// larger than `AgentContextService.perSourceCharBudget`, which that path
/// tail-truncates. Read-class, so it is gated like any other read.
@MainActor
struct MCPReadResourceTool: AgentTool {
    // `weak`, not `unowned`: in production `agentTools` and `mcpServerRegistry`
    // share `AppEnvironment`'s lifetime, so `unowned` would be safe there — but
    // a caller can construct this tool around a registry it does not otherwise
    // retain (e.g. a temporary passed straight into the initializer), and
    // `unowned` crashes the process the instant that temporary is deallocated.
    // `weak` degrades to a named error result instead.
    weak var registry: MCPServerRegistry?

    let name = "mcp_read_resource"
    let description = """
    Read the full contents of a resource published by an MCP server or Ainkrad app. \
    Use when the workspace context shows a truncated value and you need all of it.
    """
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "server": .object(["type": .string("string"),
                                   "description": .string("Server or app id that owns the resource.")]),
                "uri": .object(["type": .string("string"),
                                "description": .string("Resource URI, as reported by the server.")]),
            ]),
            "required": .array([.string("server"), .string("uri")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let server = input["server"]?.stringValue, !server.isEmpty else {
            throw ToolError.message("mcp_read_resource requires a \"server\".")
        }
        guard let uri = input["uri"]?.stringValue, !uri.isEmpty else {
            throw ToolError.message("mcp_read_resource requires a \"uri\".")
        }
        guard let registry, let client = registry.client(for: server) else {
            return ToolResult(content: "No connected MCP server named '\(server)'.", isError: true)
        }
        do {
            return ToolResult(content: try await client.readResource(uri: uri), isError: false)
        } catch {
            return ToolResult(content: "Reading '\(uri)' from '\(server)' failed: \(error)",
                              isError: true)
        }
    }
}
