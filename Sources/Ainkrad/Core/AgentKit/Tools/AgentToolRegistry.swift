// Sources/Ainkrad/Core/AgentKit/Tools/AgentToolRegistry.swift
import Foundation

@MainActor
final class AgentToolRegistry {
    private let tools: [String: any AgentTool]
    private let order: [String]

    init(tools: [any AgentTool]) {
        var map: [String: any AgentTool] = [:]
        var order: [String] = []
        for tool in tools where map[tool.name] == nil {
            map[tool.name] = tool
            order.append(tool.name)
        }
        self.tools = map
        self.order = order
    }

    func tool(named name: String) -> (any AgentTool)? { tools[name] }

    var schemas: [AgentToolSchema] { order.compactMap { tools[$0]?.schema } }

    /// Executes a call, mapping any throw or unknown-tool into an error result
    /// (the loop feeds this back to the agent as a `tool_result` with `is_error`).
    func run(_ call: ToolCall) async -> ToolResult {
        guard let tool = tools[call.name] else {
            return ToolResult(content: "Unknown tool: \(call.name)", isError: true)
        }
        do {
            return try await tool.execute(call.input)
        } catch let ToolError.message(m) {
            return ToolResult(content: m, isError: true)
        } catch {
            return ToolResult(content: error.localizedDescription, isError: true)
        }
    }
}
