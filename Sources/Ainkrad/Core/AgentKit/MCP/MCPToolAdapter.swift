// Sources/Ainkrad/Core/AgentKit/MCP/MCPToolAdapter.swift
import Foundation
import AinkradHostRuntime

/// Presents one discovered MCP tool to the LLM as a native `AgentTool`. Names
/// are namespaced `mcp/<server>/<tool>` to avoid collisions across servers and
/// with built-in tools. Trust is resolved by `MCPServerRegistry.isToolTrusted`,
/// which matches the namespaced name against the registry's REAL discovered
/// `(server, tool)` pairs by exact equality — deliberately NOT by splitting the
/// string on `/` (a server id may contain `/`, and a naive split would let one
/// server borrow another's trust). Do not "simplify" that lookup to a split.
/// MCP tools are `.write` class (gated) by default; a trusted server
/// auto-approves them via the permission seam (Task 9), never an irreversible op.
struct MCPToolAdapter: AgentTool {
    let server: String
    let descriptor: MCPToolDescriptor
    let client: MCPClient

    var name: String { "mcp/\(server)/\(descriptor.name)" }
    var description: String { descriptor.description }
    var parametersSchema: JSONValue { descriptor.inputSchema }
    let permission: ToolPermissionClass = .write

    /// Honours the server's own `annotations.destructiveHint`. Without this the
    /// Full-auto irreversible guard could never fire for ANY MCP tool, because
    /// `permission` is a constant `.write` — a trusted server's `reset --hard`
    /// would auto-approve. Whole-tool granularity only: per-CALL irreversibility
    /// (inspecting arguments) is a separate, unmade decision.
    func isIrreversible(_ input: JSONValue) -> Bool { descriptor.destructive }

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
