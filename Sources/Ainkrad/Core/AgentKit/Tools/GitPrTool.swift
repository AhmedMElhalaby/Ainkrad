// Sources/Ainkrad/Core/AgentKit/Tools/GitPrTool.swift
import Foundation
import AinkradHostRuntime

/// Dispatches a Pull-Request operation to the Git Mage plugin over the v3
/// action seam (distinct from `GitOpTool`'s local-git `gitmage.git_op`). The
/// plugin's handler drives GitHub via `gh`/the GitHub API — no PR logic lives
/// here. Returns the plugin's result text, or a graceful error when Git Mage
/// isn't installed/open OR hasn't shipped the `pr_op` handler yet.
@MainActor
struct GitPrTool: AgentTool {
    /// The namespaced action id the Git Mage plugin registers its PR handler under.
    static let seamActionID = "gitmage.pr_op"

    /// Operations the Full-auto guard treats as irreversible (see `isIrreversible`).
    ///
    /// `mergePR` is the only PR operation that cannot be undone from the API:
    /// it rewrites the base branch. Everything else here either creates
    /// something reviewable (`createPR`, `commentPR`, `reviewPR`) or is
    /// read-only — a human can revert those without a force-push.
    static let prOperations: Set<String> = ["mergePR"]

    unowned let actionHub: AgentActionRegistryHub

    let name = "pr_op"
    let description = "Perform a GitHub Pull-Request operation (createPR, listPRs, viewPR, reviewPR, commentPR, ciStatus, mergePR) via the Git Mage plugin."
    let permission: ToolPermissionClass = .write

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "operation": .object(["type": .string("string"),
                                      "description": .string("The PR operation: createPR, listPRs, viewPR, reviewPR, commentPR, ciStatus, mergePR.")]),
                "repoPath": .object(["type": .string("string"),
                                     "description": .string("Absolute path to the git repository.")]),
                "args": .object(["type": .string("object"),
                                 "description": .string("Operation arguments, e.g. {\"title\":\"…\",\"base\":\"main\"} or {\"number\":42}.")]),
            ]),
            "required": .array([.string("operation"), .string("repoPath")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let operation = input["operation"]?.stringValue, !operation.isEmpty else {
            throw ToolError.message("pr_op requires an \"operation\".")
        }
        guard input["repoPath"]?.stringValue?.isEmpty == false else {
            throw ToolError.message("pr_op requires a \"repoPath\".")
        }
        // Same boundary check `git_op` performs. The plan for this tool predates
        // that fix (written 2026-07-24; the guard landed in the audit's Wave 1),
        // but the exposure is identical and arguably worse: these values reach
        // `gh`, which forwards unknown flags to `git`, so a `--upload-pack=`/
        // `ext::sh -c` value is remote code execution by the same route. Reusing
        // `GitOpTool`'s implementation keeps the two surfaces from drifting.
        if let offending = GitOpTool.optionLookingValue(in: input) {
            throw ToolError.message(
                "pr_op refused: \"\(offending)\" starts with \"-\", which git/gh would read as an option, not a value.")
        }
        let json = payloadJSON(input)
        guard let result = await actionHub.invoke(actionID: Self.seamActionID, input: json) else {
            return ToolResult(content: "Git Mage PR support is not available; open/update the Git Mage app to run PR operations.",
                              isError: true)
        }
        return ToolResult(content: result.text, isError: result.isError)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let op = input["operation"]?.stringValue ?? "?"
        let repo = input["repoPath"]?.stringValue ?? "?"
        return ToolApprovalPreview(title: "PR: \(op)", summary: "\(op) — \(repo)", diff: nil)
    }

    func isIrreversible(_ input: JSONValue) -> Bool {
        // Defense in depth, mirroring `GitOpTool`: an option-looking value must
        // never auto-approve, even though `execute` refuses it outright.
        if GitOpTool.optionLookingValue(in: input) != nil { return true }
        guard let op = input["operation"]?.stringValue else { return false }
        return Self.prOperations.contains(op)
    }

    /// Serialize {operation, repoPath, args} as a JSON string for the plugin.
    private func payloadJSON(_ input: JSONValue) -> String {
        var obj: [String: JSONValue] = [:]
        if let op = input["operation"] { obj["operation"] = op }
        if let repo = input["repoPath"] { obj["repoPath"] = repo }
        if let args = input["args"] { obj["args"] = args }
        let data = try? JSONSerialization.data(withJSONObject: JSONValue.object(obj).toFoundationObject())
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
