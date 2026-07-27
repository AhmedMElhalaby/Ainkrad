// Tests/AinkradTests/GitPrToolRegistrationTests.swift
import Testing
@testable import Ainkrad
import AinkradHostRuntime
import AinkradAppKit

@MainActor
@Suite("pr_op registration")
struct GitPrToolRegistrationTests {
    // Guards the seam-id contract the plugin must match, and that the tool is
    // constructible exactly as bootstrap constructs it (same initializer shape
    // as GitOpTool). Full bootstrap wiring is verified by Manual verification.
    @Test func toolConstructsWithHubLikeBootstrap() {
        let hub = AgentActionRegistryHub()
        let tools: [any AgentTool] = [GitOpTool(actionHub: hub), GitPrTool(actionHub: hub)]
        #expect(tools.contains { $0.name == "pr_op" })
        #expect(tools.contains { $0.name == "git_op" })
    }

    /// `pr_op` reaches the network and can merge, so it must NOT be available to
    /// unattended runs on the same terms as an interactive one. `web_fetch`/
    /// `web_search`/`image_generate` are stripped by `isUnattendedNetworkTool`;
    /// `pr_op` is instead protected by the `unattended` auto-deny in
    /// `AgentSession`, because it is `.write` (always approval-gated) rather
    /// than read-class auto-approve. This pins that reasoning: if `pr_op` ever
    /// becomes read-class, this test should fail and force a re-think.
    @Test func prOpIsWriteClassSoUnattendedRunsAutoDenyIt() {
        let hub = AgentActionRegistryHub()   // must outlive `tool`: actionHub is `unowned`
        let tool = GitPrTool(actionHub: hub)
        #expect(tool.permission == .write)
    }
}
