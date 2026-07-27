// Tests/AinkradTests/GitPrToolGatingTests.swift
import Testing
@testable import Ainkrad
import AinkradHostRuntime
import AinkradAppKit

@MainActor
@Suite("GitPrTool gating")
struct GitPrToolGatingTests {
    // Both stored: `actionHub` is `unowned`, so the hub must outlive the tool
    // (see the note in GitPrToolPayloadTests — a temporary crashes, not fails).
    private let hub: AgentActionRegistryHub
    private let tool: GitPrTool

    init() {
        let hub = AgentActionRegistryHub()
        self.hub = hub
        self.tool = GitPrTool(actionHub: hub)
    }

    @Test func mergeIsAlwaysIrreversible() {
        let merge = JSONValue.object(["operation": .string("mergePR"), "repoPath": .string("/r")])
        #expect(tool.isIrreversible(merge))
        #expect(GitPrTool.prOperations.contains("mergePR"))
    }

    @Test func readishOpsAreReversible() {
        for op in ["createPR", "listPRs", "viewPR", "reviewPR", "commentPR", "ciStatus"] {
            let input = JSONValue.object(["operation": .string(op), "repoPath": .string("/r")])
            #expect(tool.isIrreversible(input) == false)
        }
    }

    @Test func approvalPreviewNamesOperation() {
        let input = JSONValue.object(["operation": .string("mergePR"), "repoPath": .string("/repo")])
        let preview = tool.approvalPreview(input)
        #expect(preview.title == "PR: mergePR")
        #expect(preview.summary.contains("/repo"))
        #expect(preview.diff == nil)
    }

    // MARK: - Argument-injection guard
    //
    // Not in the original plan (written before the Wave 1 `git_op` fix). These
    // freeze the same boundary for `pr_op`: values reach `gh`, which forwards
    // unknown flags to `git`, so an option-looking value is code execution.

    @Test func refusesOptionLookingValues() async throws {
        let cases: [JSONValue] = [
            .object(["operation": .string("listPRs"), "repoPath": .string("--upload-pack=touch /tmp/pwn")]),
            .object(["operation": .string("createPR"), "repoPath": .string("/r"),
                     "args": .object(["base": .string("--exec=touch /tmp/pwn")])]),
            .object(["operation": .string("createPR"), "repoPath": .string("/r"),
                     "args": .object(["head": .string("ext::sh -c touch% /tmp/pwn")])]),
            // Nested one level down — as dangerous as top-level.
            .object(["operation": .string("createPR"), "repoPath": .string("/r"),
                     "args": .object(["reviewers": .array([.string("--exec=touch /tmp/pwn")])])]),
        ]
        for input in cases {
            await #expect(throws: ToolError.self) { try await tool.execute(input) }
            // Fails safe even if `execute` ever stops refusing.
            #expect(tool.isIrreversible(input))
        }
    }
}
