// Sources/Ainkrad/Core/AgentKit/MCP/MCPToolAdapter.swift
import Foundation

/// Presents one discovered MCP tool to the LLM as a native `AgentTool`. Names
/// are namespaced `mcp/<server>/<tool>` (parsed back by
/// `MCPServerRegistry.isToolTrusted` via `split(separator: "/", maxSplits: 2)`)
/// to avoid collisions across servers and with built-in tools. MCP tools are
/// `.write` class (gated) by default; a trusted server auto-approves them via
/// the permission seam (Task 9).
struct MCPToolAdapter: AgentTool {
    let server: String
    let descriptor: MCPToolDescriptor
    let client: MCPClient

    var name: String { "mcp/\(server)/\(descriptor.name)" }
    var description: String { descriptor.description }
    var parametersSchema: JSONValue { descriptor.inputSchema }
    let permission: ToolPermissionClass = .write

    func execute(_ input: JSONValue) async throws -> ToolResult {
        do {
            let text = try await client.callTool(name: descriptor.name, arguments: input)
            return ToolResult(content: text, isError: false)
        } catch let error as MCPError {
            // Never crash the session on a server/parse failure — surface it as
            // a typed error result the LLM (and the user) can see.
            return ToolResult(content: "MCP tool \(name) failed: \(error)", isError: true)
        }
    }
}
