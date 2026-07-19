import Foundation

/// The effective outcome after composing all permission layers. `denied` is a
/// hard state distinct from `PermissionDecision` — once ANY layer excludes a
/// tool, no other layer can restore it.
enum EffectivePermission: Sendable, Equatable { case autoApprove, requireApproval, denied }

/// Human-readable explanation of an `EffectivePermission`, naming which layer
/// produced it. Never includes secrets — only the tool name and layer identity.
struct PermissionExplanation: Sendable, Equatable {
    let effective: EffectivePermission
    let reason: String
}

/// Composes the three permission layers into one effective decision:
/// 1. The global gate (`AgentPermissionPolicy.decide`'s output) — already applies
///    the irreversible-action guard; this policy never re-derives or reorders it.
/// 2. The Agent's tool allow-list (`nil` = no per-Agent restriction).
/// 3. The sandbox profile's tool allow-list (empty = defer to the other layers).
///
/// Narrowing only, most-restrictive-wins, fail-closed: an allow-list can only
/// REMOVE tools, never add them, and an exclusion at any layer is a HARD
/// `denied` that no other layer can undo. The composed result is never more
/// permissive than any single input layer.
///
/// Pure, deterministic, no I/O.
enum SandboxPermissionPolicy {
    static func compose(
        gate: PermissionDecision,
        agentAllowList: Set<String>?,
        sandboxAllowList: Set<String>,
        toolName: String
    ) -> PermissionExplanation {
        // Layer 2 — Agent tool allow-list.
        if let agent = agentAllowList, !agent.contains(toolName) {
            return PermissionExplanation(
                effective: .denied,
                reason: "\"\(toolName)\" is not in the Agent's tool allow-list.")
        }
        // Layer 3 — sandbox profile allow-list.
        if !sandboxAllowList.isEmpty, !sandboxAllowList.contains(toolName) {
            return PermissionExplanation(
                effective: .denied,
                reason: "\"\(toolName)\" is not in the sandbox profile's allow-list.")
        }
        // Layer 1 — the global gate's decision, passed through verbatim. Never
        // loosened by the presence of an allow-list entry above.
        switch gate {
        case .autoApprove:
            return PermissionExplanation(effective: .autoApprove, reason: "All layers permit.")
        case .requireApproval:
            return PermissionExplanation(
                effective: .requireApproval,
                reason: "The global permission gate requires approval.")
        }
    }
}
