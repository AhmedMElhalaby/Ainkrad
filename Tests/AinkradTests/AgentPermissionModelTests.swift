import Testing
@testable import Ainkrad

@Suite("AgentPermissionPolicy")
struct AgentPermissionModelTests {
    private func decide(_ p: ToolPermissionClass, _ mode: AgentPermissionMode,
                        name: String = "edit_file", allow: Set<String> = [],
                        gateReads: Bool, isIrreversible: Bool = false) -> PermissionDecision {
        AgentPermissionPolicy.decide(toolPermission: p, toolName: name, mode: mode, allowlist: allow,
                                     gateReads: gateReads, isIrreversible: isIrreversible)
    }

    @Test func askAutoApprovesReadsGatesWrites() {
        #expect(decide(.read, .ask, gateReads: false) == .autoApprove)
        #expect(decide(.write, .ask, gateReads: false) == .requireApproval)
    }

    @Test func autoApproveGatesWritesUnlessAllowlisted() {
        #expect(decide(.read, .autoApprove, gateReads: false) == .autoApprove)
        #expect(decide(.write, .autoApprove, gateReads: false) == .requireApproval)
        #expect(decide(.write, .autoApprove, name: "edit_file", allow: ["edit_file"], gateReads: false) == .autoApprove)
    }

    @Test func fullAutoApprovesEverything() {
        #expect(decide(.read, .fullAuto, gateReads: false) == .autoApprove)
        #expect(decide(.write, .fullAuto, gateReads: false) == .autoApprove)
    }

    @Test func gateReadsAskGatesReads() {
        #expect(decide(.read, .ask, gateReads: true) == .requireApproval)
        #expect(decide(.write, .ask, gateReads: true) == .requireApproval)
    }

    @Test func gateReadsAutoApproveGatesReadsUnlessAllowlisted() {
        #expect(decide(.read, .autoApprove, gateReads: true) == .requireApproval)
        #expect(decide(.read, .autoApprove, name: "read_file", allow: ["read_file"], gateReads: true) == .autoApprove)
        #expect(decide(.write, .autoApprove, gateReads: true) == .requireApproval)
    }

    @Test func gateReadsFullAutoStillApprovesEverything() {
        #expect(decide(.read, .fullAuto, gateReads: true) == .autoApprove)
        #expect(decide(.write, .fullAuto, gateReads: true) == .autoApprove)
    }

    @Test("fullAuto still gates irreversible calls")
    func fullAutoGatesIrreversible() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .write, toolName: "git_op", mode: .fullAuto,
            allowlist: [], gateReads: false, isIrreversible: true)
        #expect(d == .requireApproval)
    }

    @Test("fullAuto auto-approves reversible calls")
    func fullAutoAutoApprovesReversible() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .write, toolName: "run_terminal", mode: .fullAuto,
            allowlist: [], gateReads: false, isIrreversible: false)
        #expect(d == .autoApprove)
    }

    @Test("isIrreversible does not change ask behavior (writes already gated)")
    func nonFullAutoUnaffectedByIrreversible() {
        // Writes already require approval in .ask, regardless of isIrreversible.
        #expect(decide(.write, .ask, gateReads: false, isIrreversible: true) == .requireApproval)
        #expect(decide(.write, .ask, gateReads: false, isIrreversible: false) == .requireApproval)
    }

    @Test("autoApprove: allowlisted tool + irreversible call still requires approval (bypass closed)")
    func autoApproveAllowlistedIrreversibleStillGated() {
        // This is the bug: "Allow always" allowlists the whole tool NAME, so a later
        // irreversible call (e.g. `rm -rf`) through that same tool must NOT slip through.
        #expect(decide(.write, .autoApprove, name: "run_terminal", allow: ["run_terminal"], gateReads: false, isIrreversible: true) == .requireApproval)
    }

    @Test("autoApprove: allowlisted tool + reversible call is unchanged (still auto-approves)")
    func autoApproveAllowlistedReversibleUnchanged() {
        #expect(decide(.write, .autoApprove, name: "edit_file", allow: ["edit_file"], gateReads: false, isIrreversible: false) == .autoApprove)
    }
}
