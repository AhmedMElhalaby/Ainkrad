// Sources/Ainkrad/Core/AgentKit/Agents/BuiltInAgents.swift
import Foundation

enum BuiltInAgents {
    static let planID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let buildID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    static let plan = AgentProfile(
        id: planID, name: "Plan",
        instructions: """
        You are in PLAN mode. Investigate, read, and reason — but do not modify \
        files, run commands, or mutate git. Produce a clear plan and ask before acting.
        """,
        toolPolicy: .restricted(allow: [], deny: [], allowClasses: [.read]),
        permissionPosture: nil,
        routing: AgentRouting(routerEnabled: true),
        builtin: true,
        icon: "list.bullet.clipboard")

    static let build = AgentProfile(
        id: buildID, name: "Build",
        instructions: """
        You are in BUILD mode. Read, edit, run commands, and use git via the \
        provided tools, respecting the approval gate.
        """,
        toolPolicy: .all,
        permissionPosture: nil,
        routing: AgentRouting(routerEnabled: true),
        builtin: true,
        icon: "hammer")

    static let all: [AgentProfile] = [plan, build]
}
