import Foundation

enum AgentPermissionMode: String, Codable, CaseIterable, Sendable {
    case ask, autoApprove, fullAuto
}

enum PermissionDecision: Sendable, Equatable { case autoApprove, requireApproval }

enum AgentPermissionPolicy {
    /// Decide whether a pending tool call runs unattended or must hit the HUD.
    /// - `ask`: reads auto-approve unless `gateReads`; writes always require approval.
    /// - `autoApprove`: allowlisted tools auto-approve; reads auto-approve unless `gateReads`;
    ///   other writes require approval.
    /// - `fullAuto`: everything (writes included) auto-approves, regardless of `gateReads`.
    static func decide(
        toolPermission: ToolPermissionClass,
        toolName: String,
        mode: AgentPermissionMode,
        allowlist: Set<String>,
        gateReads: Bool
    ) -> PermissionDecision {
        switch mode {
        case .fullAuto:
            return .autoApprove
        case .ask:
            return (toolPermission == .read && !gateReads) ? .autoApprove : .requireApproval
        case .autoApprove:
            if allowlist.contains(toolName) { return .autoApprove }
            return (toolPermission == .read && !gateReads) ? .autoApprove : .requireApproval
        }
    }
}
