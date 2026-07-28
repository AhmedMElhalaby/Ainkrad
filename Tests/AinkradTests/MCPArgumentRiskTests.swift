// Tests/AinkradTests/MCPArgumentRiskTests.swift
import Testing
import AinkradHostRuntime
@testable import Ainkrad

@Suite("MCPArgumentRisk")
struct MCPArgumentRiskTests {
    @Test("a plain payload carries no option-looking value")
    func plainPayloadIsClean() {
        #expect(!MCPArgumentRisk.hasOptionLookingValue(.object([
            "repoPath": .string("/tmp/repo"), "message": .string("fix: thing"),
        ])))
    }

    @Test("a leading-dash value anywhere is flagged")
    func leadingDashIsFlagged() {
        #expect(MCPArgumentRisk.hasOptionLookingValue(.object([
            "branch": .string("--upload-pack=/bin/sh"),
        ])))
    }

    @Test("recurses into nested arrays and objects")
    func recursesIntoNestedValues() {
        #expect(MCPArgumentRisk.hasOptionLookingValue(.object([
            "args": .object(["paths": .array([.string("ok"), .string("--exec=sh")])]),
        ])))
    }

    @Test("the ext:: transport helper is flagged even without a dash")
    func extTransportIsFlagged() {
        #expect(MCPArgumentRisk.hasOptionLookingValue(.object([
            "url": .string("ext::sh -c whoami"),
        ])))
    }

    // The rule only ever inspects `.string` values for option-looking
    // forms — a `.number` can never match `hasPrefix`/`ext::`. So this
    // doesn't prove some special negative-number carve-out; it proves the
    // walk doesn't misfire on non-string JSON at all.
    @Test("a bare negative number is not an option")
    func negativeNumberIsNotAnOption() {
        #expect(!MCPArgumentRisk.hasOptionLookingValue(.object(["count": .number(-5)])))
    }

    @Test("a single top-level leading-dash string is flagged")
    func topLevelLeadingDashIsFlagged() {
        #expect(MCPArgumentRisk.hasOptionLookingValue(.string("-c")))
    }

    @Test("ext:: is case-insensitively flagged")
    func extTransportIsCaseInsensitive() {
        #expect(MCPArgumentRisk.hasOptionLookingValue(.object([
            "url": .string("EXT::sh -c whoami"),
        ])))
    }

    @Test("a short-form leading-dash flag is flagged")
    func shortFormDashIsFlagged() {
        #expect(MCPArgumentRisk.hasOptionLookingValue(.object([
            "opt": .string("-c core.pager=sh"),
        ])))
    }
}
