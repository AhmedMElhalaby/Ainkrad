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

    /// Honours the server's own `annotations.destructiveHint` OR'd with a
    /// per-call argument-risk check. `destructiveHint` alone is a static
    /// per-tool boolean and can't express per-call irreversibility (a `git_op`
    /// style tool with a benign-looking `operation` but an
    /// `--upload-pack=<cmd>` argument). `MCPArgumentRisk` generalizes
    /// `GitOpTool.optionLookingValue` off git so that hole is closed for every
    /// MCP tool, not just git's.
    ///
    /// The OR is one-directional by design: hints may only ESCALATE, never
    /// de-escalate. A server declaring `destructive: false` (or `readOnly:
    /// true`) must never be able to bypass the argument-risk check — do not
    /// "simplify" this into a short-circuit that trusts the hint when it says
    /// safe.
    func isIrreversible(_ input: JSONValue) -> Bool {
        descriptor.destructive || MCPArgumentRisk.hasOptionLookingValue(input)
    }

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
