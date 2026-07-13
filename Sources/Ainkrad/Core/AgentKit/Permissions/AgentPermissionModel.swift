import Foundation

enum AgentPermissionMode: String, Codable, CaseIterable, Sendable {
    case ask, autoApprove, fullAuto
}

enum PermissionDecision: Sendable, Equatable { case autoApprove, requireApproval }

enum AgentPermissionPolicy {
    /// Decide whether a pending tool call runs unattended or must hit the HUD.
    /// - `ask`: reads auto-approve; writes require approval.
    /// - `autoApprove`: reads and allowlisted tools auto-approve; other writes require approval.
    /// - `fullAuto`: everything (writes included) auto-approves.
    static func decide(
        toolPermission: ToolPermissionClass,
        toolName: String,
        mode: AgentPermissionMode,
        allowlist: Set<String>
    ) -> PermissionDecision {
        switch mode {
        case .fullAuto:
            return .autoApprove
        case .ask:
            return toolPermission == .read ? .autoApprove : .requireApproval
        case .autoApprove:
            if toolPermission == .read || allowlist.contains(toolName) { return .autoApprove }
            return .requireApproval
        }
    }
}
