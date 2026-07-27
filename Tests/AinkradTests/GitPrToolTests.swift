// Tests/AinkradTests/GitPrToolTests.swift
import Testing
@testable import Ainkrad
import AinkradHostRuntime
import AinkradAppKit

@MainActor
@Suite("GitPrTool")
struct GitPrToolTests {
    private func hubWithStub(_ reply: @escaping @MainActor (String) async -> AgentActionResult) -> AgentActionRegistryHub {
        let hub = AgentActionRegistryHub()
        _ = hub.register(appID: "gitmage", actionID: GitPrTool.seamActionID, handler: reply)
        return hub
    }

    @Test func forwardsPluginResultVerbatim() async throws {
        let hub = hubWithStub { input in
            AgentActionResult(text: "PR #42 created: \(input.contains("createPR"))", isError: false)
        }
        let tool = GitPrTool(actionHub: hub)
        let input = JSONValue.object([
            "operation": .string("createPR"),
            "repoPath": .string("/repo"),
            "args": .object(["title": .string("Add feature"), "base": .string("main")]),
        ])
        let result = try await tool.execute(input)
        #expect(result.isError == false)
        #expect(result.content.contains("PR #42 created: true"))
    }

    @Test func identityAndSchema() {
        let hub = AgentActionRegistryHub()   // must outlive `tool`: actionHub is `unowned`
        let tool = GitPrTool(actionHub: hub)
        #expect(tool.name == "pr_op")
        #expect(tool.permission == .write)
        #expect(GitPrTool.seamActionID == "gitmage.pr_op")
        // `JSONValue` has no `arrayValue` accessor (only `stringValue`), so the
        // plan's `["required"]?.arrayValue?.count` is matched structurally here.
        guard case .array(let required)? = tool.parametersSchema["required"] else {
            Issue.record("schema is missing a `required` array")
            return
        }
        #expect(required.count == 2)
    }
}
