// Sources/Ainkrad/Core/AgentKit/Agents/AgentProfile.swift
import Foundation

enum ModelTierCode: String, Codable, Sendable, CaseIterable {
    case local, free, cheapPaid, premium
}

struct AgentRouting: Codable, Equatable, Sendable {
    var routerEnabled: Bool
    var preferredModels: [String]
    var allowedModels: [String]   // empty = unrestricted
    var maxTier: ModelTierCode?   // nil = no ceiling

    init(routerEnabled: Bool = true, preferredModels: [String] = [],
         allowedModels: [String] = [], maxTier: ModelTierCode? = nil) {
        self.routerEnabled = routerEnabled
        self.preferredModels = preferredModels
        self.allowedModels = allowedModels
        self.maxTier = maxTier
    }
}

struct AgentProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var instructions: String
    var toolPolicy: AgentToolPolicy
    var defaultModel: String?
    /// nil = inherit the workspace permission mode; non-nil composes
    /// most-restrictive-wins with it (Task 4 `effectiveMode()`).
    var permissionPosture: AgentPermissionMode?
    var routing: AgentRouting
    let builtin: Bool

    init(id: UUID = UUID(), name: String, instructions: String,
         toolPolicy: AgentToolPolicy, defaultModel: String? = nil,
         permissionPosture: AgentPermissionMode? = nil,
         routing: AgentRouting = AgentRouting(), builtin: Bool = false) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.toolPolicy = toolPolicy
        self.defaultModel = defaultModel
        self.permissionPosture = permissionPosture
        self.routing = routing
        self.builtin = builtin
    }

    static func custom(name: String, instructions: String) -> AgentProfile {
        AgentProfile(name: name, instructions: instructions, toolPolicy: .all)
    }
}
