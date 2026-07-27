// Tests/AinkradTests/GitPrToolPayloadTests.swift
import Testing
@testable import Ainkrad
import AinkradHostRuntime
import AinkradAppKit

@MainActor
@Suite("GitPrTool payload & availability")
struct GitPrToolPayloadTests {

    // `GitPrTool.actionHub` is `unowned` (mirroring `GitOpTool`, so the tool
    // can't retain the environment-owned hub). That makes an inline
    // `GitPrTool(actionHub: AgentActionRegistryHub())` a use-after-free: the
    // temporary dies before `execute` reads it. The hub MUST be held by a
    // local/property for the tool's lifetime — as `AppEnvironment` does in
    // production. Written out because it crashes rather than fails.
    @Test func returnsGracefulErrorWhenPluginAbsent() async throws {
        let hub = AgentActionRegistryHub()                          // nothing registered
        let tool = GitPrTool(actionHub: hub)
        let input = JSONValue.object(["operation": .string("listPRs"), "repoPath": .string("/r")])
        let result = try await tool.execute(input)
        #expect(result.isError)
        #expect(result.content.contains("not available"))
    }

    @Test func throwsOnMissingOperation() async throws {
        let hub = AgentActionRegistryHub()
        let tool = GitPrTool(actionHub: hub)
        let input = JSONValue.object(["repoPath": .string("/r")])
        await #expect(throws: ToolError.self) { try await tool.execute(input) }
    }

    @Test func throwsOnMissingRepoPath() async throws {
        let hub = AgentActionRegistryHub()
        let tool = GitPrTool(actionHub: hub)
        let input = JSONValue.object(["operation": .string("listPRs")])
        await #expect(throws: ToolError.self) { try await tool.execute(input) }
    }

    @Test func forwardsArgsIntact() async throws {
        let hub = AgentActionRegistryHub()
        let box = Box()
        _ = hub.register(appID: "gitmage", actionID: GitPrTool.seamActionID) { input in
            box.captured = input
            return AgentActionResult(text: "ok", isError: false)
        }
        let tool = GitPrTool(actionHub: hub)
        let input = JSONValue.object([
            "operation": .string("mergePR"),
            "repoPath": .string("/repo"),
            "args": .object(["number": .number(7), "method": .string("squash")]),
        ])
        _ = try await tool.execute(input)
        #expect(box.captured?.contains("\"mergePR\"") == true)
        #expect(box.captured?.contains("/repo") == true)
        #expect(box.captured?.contains("squash") == true)
    }

    /// The seam id is a cross-repo contract: the Git Mage plugin registers this
    /// exact string. Changing it silently breaks PR support at runtime with only
    /// the graceful "not available" message, so it is pinned literally here.
    @Test func seamIDIsTheCrossRepoContract() {
        #expect(GitPrTool.seamActionID == "gitmage.pr_op")
        // Must stay distinct from the local-git seam so `git_op` stays frozen.
        #expect(GitPrTool.seamActionID != "gitmage.git_op")
    }

    @MainActor final class Box { var captured: String? }
}
