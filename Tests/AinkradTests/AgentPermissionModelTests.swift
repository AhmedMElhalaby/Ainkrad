import Testing
@testable import Ainkrad

@Suite("AgentPermissionPolicy")
struct AgentPermissionModelTests {
    private func decide(_ p: ToolPermissionClass, _ mode: AgentPermissionMode,
                        name: String = "edit_file", allow: Set<String> = []) -> PermissionDecision {
        AgentPermissionPolicy.decide(toolPermission: p, toolName: name, mode: mode, allowlist: allow)
    }

    @Test func askAutoApprovesReadsGatesWrites() {
        #expect(decide(.read, .ask) == .autoApprove)
        #expect(decide(.write, .ask) == .requireApproval)
    }

    @Test func autoApproveGatesWritesUnlessAllowlisted() {
        #expect(decide(.read, .autoApprove) == .autoApprove)
        #expect(decide(.write, .autoApprove) == .requireApproval)
        #expect(decide(.write, .autoApprove, name: "edit_file", allow: ["edit_file"]) == .autoApprove)
    }

    @Test func fullAutoApprovesEverything() {
        #expect(decide(.read, .fullAuto) == .autoApprove)
        #expect(decide(.write, .fullAuto) == .autoApprove)
    }
}
