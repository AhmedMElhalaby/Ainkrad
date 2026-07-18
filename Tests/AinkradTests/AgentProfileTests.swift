// Tests/AinkradTests/AgentProfileTests.swift
import Foundation
import Testing
@testable import Ainkrad

@Suite("AgentProfile")
struct AgentProfileTests {
    @Test func customFactorySaneDefaults() {
        let a = AgentProfile.custom(name: "Reviewer", instructions: "Review carefully.")
        #expect(a.builtin == false)
        #expect(a.toolPolicy == .all)
        #expect(a.routing.routerEnabled)
        #expect(a.routing.maxTier == nil)
        #expect(a.permissionPosture == nil)   // nil = inherit workspace mode
    }

    @Test func codableRoundTrips() throws {
        var a = AgentProfile.custom(name: "R", instructions: "x")
        a.routing = AgentRouting(routerEnabled: false, preferredModels: ["m"], allowedModels: ["m"], maxTier: .cheapPaid)
        a.defaultModel = "gpt-5-mini"
        let data = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(AgentProfile.self, from: data) == a)
    }
}
