// Sources/Ainkrad/Core/AgentKit/Tools/WorkspaceControlTool.swift
import Foundation
import AinkradHostRuntime

/// Host-native tool that drives the workspace layer via `WorkspaceManager`.
/// Scoped to the manager's existing verbs. `deleteWorkspace` is irreversible.
@MainActor
struct WorkspaceControlTool: AgentTool {
    unowned let workspaces: WorkspaceManager

    let name = "workspace_control"
    let description = """
    Rearrange the workspace: create/delete workspaces, move or duplicate an open \
    app between workspaces, and switch the active workspace.
    """
    let permission: ToolPermissionClass = .write

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("createWorkspace"), .string("deleteWorkspace"),
                        .string("moveApp"), .string("duplicateApp"),
                        .string("switchTo"), .string("switchToWorkspace"),
                        .string("switchToNextWorkspace"), .string("switchToPreviousWorkspace"),
                    ]),
                    "description": .string("The workspace operation to perform."),
                ]),
                "id": .object(["type": .string("string"),
                               "description": .string("Workspace UUID (deleteWorkspace, switchTo).")]),
                "index": .object(["type": .string("integer"),
                                  "description": .string("0-based workspace index (switchToWorkspace).")]),
                "blockID": .object(["type": .string("string"),
                                    "description": .string("Open app block UUID (moveApp).")]),
                "from": .object(["type": .string("string"),
                                 "description": .string("Source workspace UUID (moveApp).")]),
                "to": .object(["type": .string("string"),
                               "description": .string("Destination workspace UUID (moveApp, duplicateApp).")]),
                "appID": .object(["type": .string("string"),
                                  "description": .string("App id to duplicate (duplicateApp).")]),
            ]),
            "required": .array([.string("action")]),
        ])
    }

    private func uuid(_ input: JSONValue, _ key: String) throws -> UUID {
        guard let s = input[key]?.stringValue, let id = UUID(uuidString: s) else {
            throw ToolError.message("workspace_control \(key) must be a valid UUID string.")
        }
        return id
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let action = input["action"]?.stringValue else {
            throw ToolError.message("workspace_control requires an \"action\".")
        }
        switch action {
        case "createWorkspace":
            let ws = workspaces.createWorkspace()
            return ToolResult(content: "Created workspace \(ws.name) (\(ws.id.uuidString)).", isError: false)
        case "deleteWorkspace":
            let id = try uuid(input, "id")
            workspaces.deleteWorkspace(id)
            return ToolResult(content: "Deleted workspace \(id.uuidString).", isError: false)
        case "moveApp":
            let block = try uuid(input, "blockID")
            let from = try uuid(input, "from")
            let to = try uuid(input, "to")
            workspaces.moveApp(block, from: from, to: to)
            return ToolResult(content: "Moved app \(block.uuidString) to \(to.uuidString).", isError: false)
        case "duplicateApp":
            guard let appID = input["appID"]?.stringValue, !appID.isEmpty else {
                throw ToolError.message("duplicateApp requires \"appID\".")
            }
            let to = try uuid(input, "to")
            workspaces.duplicateApp(appID, to: to)
            return ToolResult(content: "Duplicated \(appID) into \(to.uuidString).", isError: false)
        case "switchTo":
            let id = try uuid(input, "id")
            workspaces.switchTo(id)
            return ToolResult(content: "Switched to workspace \(id.uuidString).", isError: false)
        case "switchToWorkspace":
            guard case .number(let n)? = input["index"] else {
                throw ToolError.message("switchToWorkspace requires an integer \"index\".")
            }
            guard n.isFinite, n == n.rounded(), n >= 0, n <= Double(Int32.max) else {
                return ToolResult(
                    content: "switchToWorkspace requires a valid non-negative integer index.",
                    isError: true
                )
            }
            workspaces.switchToWorkspace(at: Int(n))
            return ToolResult(content: "Switched to workspace index \(Int(n)).", isError: false)
        case "switchToNextWorkspace":
            workspaces.switchToNextWorkspace()
            return ToolResult(content: "Switched to the next workspace.", isError: false)
        case "switchToPreviousWorkspace":
            workspaces.switchToPreviousWorkspace()
            return ToolResult(content: "Switched to the previous workspace.", isError: false)
        default:
            return ToolResult(content: "Unknown workspace action: \(action).", isError: true)
        }
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let action = input["action"]?.stringValue ?? "?"
        return ToolApprovalPreview(title: "Workspace: \(action)", summary: action, diff: nil)
    }

    func isIrreversible(_ input: JSONValue) -> Bool {
        input["action"]?.stringValue == "deleteWorkspace"
    }
}
