import Testing
@testable import Ainkrad

@Suite("AgentPermissionPolicy")
struct AgentPermissionModelTests {
    private func decide(_ p: ToolPermissionClass, _ mode: AgentPermissionMode,
                        name: String = "edit_file", allow: Set<String> = [],
                        gateReads: Bool) -> PermissionDecision {
        AgentPermissionPolicy.decide(toolPermission: p, toolName: name, mode: mode, allowlist: allow, gateReads: gateReads)
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
}
