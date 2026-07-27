import Foundation

/// A Codable mirror of `ToolPermissionClass` (which is intentionally not Codable).
enum ToolPermissionClassCode: String, Codable, Sendable, CaseIterable {
    case read, write, memory

    init(_ permission: ToolPermissionClass) {
        switch permission {
        case .read: self = .read
        case .write: self = .write
        case .memory: self = .memory
        }
    }
}

/// An Agent's tool policy. It only ever NARROWS the permission gate — a call
/// runs when this policy allows it AND `AgentPermissionPolicy.decide` approves.
enum AgentToolPolicy: Codable, Equatable, Sendable {
    case all
    case restricted(allow: Set<String>, deny: Set<String>, allowClasses: Set<ToolPermissionClassCode>)

    func allows(toolName: String, permission: ToolPermissionClass) -> Bool {
        switch self {
        case .all:
            return true
        case .restricted(let allow, let deny, let allowClasses):
            if deny.contains(toolName) { return false }
            if allow.contains(toolName) { return true }
            return allowClasses.contains(ToolPermissionClassCode(permission))
        }
    }
}
