// Sources/Ainkrad/Core/AgentKit/Tools/GitOpTool.swift
import Foundation

/// Dispatches a git operation to the Git Mage plugin over the v3 action seam.
/// The plugin's handler is a thin adapter over its `GitRepositoryClient` actor
/// (local git only — no git re-implementation here). Returns the plugin's
/// result text, or an error when Git Mage isn't installed/open.
@MainActor
struct GitOpTool: AgentTool {
    /// Operations the Full-auto guard treats as irreversible (destructive).
    /// Operation tokens that are always destructive. `reset` (mode "hard") and
    /// `removeWorktree` (force) are additionally guarded in `isIrreversible`.
    static let destructiveOperations: Set<String> = [
        "push", "deleteBranch", "deleteTag", "abortOperation",
        "rebase", "cherryPick", "revert",
    ]

    unowned let actionHub: AgentActionRegistryHub

    let name = "git_op"
    let description = "Perform a local git operation (status, commit, branch, checkout, push, pull, stash, …) via the Git Mage plugin."
    let permission: ToolPermissionClass = .write

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "operation": .object(["type": .string("string"),
                                      "description": .string("The git operation: status, commit, createBranch, checkout, deleteBranch, push, pull, fetch, stashPush, stashPop, stageAll, unstageAll, log, rebase, cherryPick, revert, reset, createTag, deleteTag, tags, removeWorktree, opState, continueOp, abortOperation.")]),
                "repoPath": .object(["type": .string("string"),
                                     "description": .string("Absolute path to the git repository.")]),
                "args": .object(["type": .string("object"),
                                 "description": .string("Operation arguments, e.g. {\"message\":\"…\"} or {\"name\":\"feature\"}.")]),
            ]),
            "required": .array([.string("operation"), .string("repoPath")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let operation = input["operation"]?.stringValue, !operation.isEmpty else {
            throw ToolError.message("git_op requires an \"operation\".")
        }
        guard input["repoPath"]?.stringValue?.isEmpty == false else {
            throw ToolError.message("git_op requires a \"repoPath\".")
        }
        let json = payloadJSON(input)
        guard let result = await actionHub.invoke(actionID: "gitmage.git_op", input: json) else {
            return ToolResult(content: "Git Mage is not available; open the Git Mage app to run git operations.",
                              isError: true)
        }
        return ToolResult(content: result.text, isError: result.isError)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let op = input["operation"]?.stringValue ?? "?"
        let repo = input["repoPath"]?.stringValue ?? "?"
        return ToolApprovalPreview(title: "Git: \(op)", summary: "\(op) — \(repo)", diff: nil)
    }

    func isIrreversible(_ input: JSONValue) -> Bool {
        guard let op = input["operation"]?.stringValue else { return false }
        if Self.destructiveOperations.contains(op) { return true }
        let args = input["args"]
        if op == "reset", args?["mode"]?.stringValue == "hard" { return true }
        if op == "removeWorktree", case .bool(true)? = args?["force"] { return true }
        return false
    }

    /// Serialize {operation, args, repoPath} as a JSON string for the plugin.
    private func payloadJSON(_ input: JSONValue) -> String {
        var obj: [String: JSONValue] = [:]
        if let op = input["operation"] { obj["operation"] = op }
        if let repo = input["repoPath"] { obj["repoPath"] = repo }
        if let args = input["args"] { obj["args"] = args }
        let data = try? JSONSerialization.data(withJSONObject: JSONValue.object(obj).toFoundationObject())
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
