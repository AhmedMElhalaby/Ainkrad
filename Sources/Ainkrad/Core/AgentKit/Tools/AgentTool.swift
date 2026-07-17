// Sources/Ainkrad/Core/AgentKit/Tools/AgentTool.swift
import Foundation

struct AgentToolSchema: Sendable, Equatable {
    let name: String
    let description: String
    let parameters: JSONValue   // JSON Schema object
}

enum ToolPermissionClass: Sendable { case read, write }

struct ToolResult: Sendable, Equatable {
    let content: String
    let isError: Bool
}

struct ToolCall: Sendable, Equatable {
    let id: String
    let name: String
    let input: JSONValue
}

/// A human-facing summary the approval HUD renders before a gated tool runs.
struct ToolApprovalPreview: Sendable, Equatable {
    let title: String
    let summary: String
    let diff: String?
}

enum ToolError: Error, Equatable { case message(String) }

@MainActor
protocol AgentTool {
    var name: String { get }
    var description: String { get }
    var parametersSchema: JSONValue { get }
    var permission: ToolPermissionClass { get }
    func execute(_ input: JSONValue) async throws -> ToolResult
    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview
    /// Whether THIS specific call is irreversible (destructive). The Full-auto
    /// guard routes irreversible calls to the approval HUD even in `.fullAuto`.
    func isIrreversible(_ input: JSONValue) -> Bool
}

extension AgentTool {
    var schema: AgentToolSchema {
        AgentToolSchema(name: name, description: description, parameters: parametersSchema)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let data = try? JSONSerialization.data(withJSONObject: input.toFoundationObject(),
                                               options: [.sortedKeys])
        let summary = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return ToolApprovalPreview(title: name, summary: summary, diff: nil)
    }

    func isIrreversible(_ input: JSONValue) -> Bool { false }
}
