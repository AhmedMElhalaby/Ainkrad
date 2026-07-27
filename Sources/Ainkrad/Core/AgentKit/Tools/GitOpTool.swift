// Sources/Ainkrad/Core/AgentKit/Tools/GitOpTool.swift
import Foundation
import AinkradHostRuntime

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
        guard let repoPath = input["repoPath"]?.stringValue, !repoPath.isEmpty else {
            throw ToolError.message("git_op requires a \"repoPath\".")
        }
        if let offending = Self.optionLookingValue(in: input) {
            throw ToolError.message(
                "git_op refused: \"\(offending)\" starts with \"-\", which git would read as an option, not a value.")
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

    /// The first `args`/`repoPath` value that git would read as an option
    /// rather than as data, or nil when every value is safe.
    ///
    /// This is the fix for the argument-injection blocker. Destructiveness was
    /// derived purely from the `operation` token, so
    /// `{"operation":"reset","mode":"soft","ref":"--hard"}` looked harmless and
    /// auto-approved in Full-auto while actually running `git reset --hard`.
    /// The same hole reached further: a clone URL of `--upload-pack=<cmd>` or
    /// `ext::sh -c <cmd>`, or a rebase base of `--exec=<cmd>`, is arbitrary code
    /// execution.
    ///
    /// A leading `-` is rejected outright rather than escaped, because it is
    /// never legitimate: `git check-ref-format` forbids refs beginning with
    /// `-`, and no branch, tag, path or remote name may start with one. There
    /// is nothing to preserve. (`--` option termination at each git call site is
    /// the *other* half of this fix and lives in GitMage; this boundary check
    /// holds even if a call site there is missed.)
    static func optionLookingValue(in input: JSONValue) -> String? {
        if let repo = input["repoPath"]?.stringValue, repo.hasPrefix("-") { return repo }
        guard case .object(let args)? = input["args"] else { return nil }
        // Sorted so the reported value is deterministic across runs — an
        // unordered dictionary would make the error message flap.
        for key in args.keys.sorted() {
            guard let value = args[key] else { continue }
            if let offending = firstOptionLooking(value) { return offending }
        }
        return nil
    }

    /// Recurses into arrays/objects — an injected option nested one level down
    /// (`{"paths": ["--exec=…"]}`) is exactly as dangerous as a top-level one.
    private static func firstOptionLooking(_ value: JSONValue) -> String? {
        switch value {
        case .string(let s):
            if s.hasPrefix("-") { return s }
            // `ext::sh -c …` is git's own transport-helper escape hatch: it runs
            // an arbitrary command, and it needs no leading dash to do it.
            if s.lowercased().hasPrefix("ext::") { return s }
            return nil
        case .array(let items):
            for item in items { if let found = firstOptionLooking(item) { return found } }
            return nil
        case .object(let dict):
            for key in dict.keys.sorted() {
                if let v = dict[key], let found = firstOptionLooking(v) { return found }
            }
            return nil
        default:
            return nil
        }
    }

    func isIrreversible(_ input: JSONValue) -> Bool {
        // Defense in depth: even though `execute` refuses these outright, an
        // option-looking value must never be able to auto-approve. If the two
        // checks ever drift, this one fails safe.
        if Self.optionLookingValue(in: input) != nil { return true }
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
