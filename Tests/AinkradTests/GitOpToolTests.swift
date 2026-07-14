import Testing
import Foundation
import AinkradAppKit
@testable import Ainkrad

@MainActor
@Suite("GitOpTool")
struct GitOpToolTests {
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    @Test("forwards to gitmage.git_op and returns its result text")
    func forwards() async throws {
        let hub = AgentActionRegistryHub()
        var received: String?
        _ = hub.register(appID: "gitmage", actionID: "gitmage.git_op") { json in
            received = json
            return AgentActionResult(text: "On branch main", isError: false)
        }
        let tool = GitOpTool(actionHub: hub)
        let result = try await tool.execute(obj([
            "operation": .string("status"),
            "repoPath": .string("/tmp/repo"),
        ]))
        #expect(!result.isError)
        #expect(result.content == "On branch main")
        let json = try #require(received)
        #expect(json.contains("\"operation\""))
        #expect(json.contains("status"))
    }

    @Test("returns an error when Git Mage is not available")
    func unavailable() async throws {
        let hub = AgentActionRegistryHub()   // nothing registered
        let tool = GitOpTool(actionHub: hub)
        let result = try await tool.execute(obj([
            "operation": .string("status"), "repoPath": .string("/tmp/repo"),
        ]))
        #expect(result.isError)
        #expect(result.content.contains("Git Mage"))
    }

    @Test("flags destructive operations irreversible")
    func irreversible() {
        let tool = GitOpTool(actionHub: AgentActionRegistryHub())
        #expect(tool.isIrreversible(obj(["operation": .string("push")])))
        #expect(tool.isIrreversible(obj(["operation": .string("deleteBranch")])))
        #expect(!tool.isIrreversible(obj(["operation": .string("status")])))
    }
}
