import Testing
import SwiftUI
@testable import Ainkrad

@Suite("Theme")
struct ThemeTests {
    @Test("neonBlue is the first case (the default theme)")
    func neonBlueIsDefault() {
        #expect(Theme.allCases.first == .neonBlue)
    }

    @Test("exactly two themes exist for M1")
    func exactlyTwoThemes() {
        #expect(Theme.allCases.count == 2)
        #expect(Theme.allCases.contains(.cyberPurple))
    }
}

@Suite("DesignTokens")
struct DesignTokensTests {
    @Test("Neon Blue tokens match the documented hex values")
    func neonBlueMatchesDocumentedValues() {
        let tokens = DesignTokens.neonBlue
        #expect(tokens.background == Color(hex: "0A0E17"))
        #expect(tokens.surface == Color(hex: "111827"))
        #expect(tokens.surfaceElevated == Color(hex: "1A2233"))
        #expect(tokens.accentPrimary == Color(hex: "2563EB"))
        #expect(tokens.accentSecondary == Color(hex: "22D3EE"))
        #expect(tokens.accentTertiary == Color(hex: "10B981"))
        #expect(tokens.foreground == Color(hex: "E2E8F0"))
    }

    @Test("Cyber Purple tokens match the documented hex values")
    func cyberPurpleMatchesDocumentedValues() {
        let tokens = DesignTokens.cyberPurple
        #expect(tokens.background == Color(hex: "080814"))
        #expect(tokens.surface == Color(hex: "141420"))
        #expect(tokens.surfaceElevated == Color(hex: "1F182E"))
        #expect(tokens.accentPrimary == Color(hex: "7C1AED"))
        #expect(tokens.accentSecondary == Color(hex: "C084FC"))
        #expect(tokens.accentTertiary == Color(hex: "EC4899"))
        #expect(tokens.foreground == Color(hex: "EDE9FE"))
    }

    @Test("Theme.tokens resolves to the matching static palette")
    func themeResolvesToMatchingPalette() {
        #expect(Theme.neonBlue.tokens == DesignTokens.neonBlue)
        #expect(Theme.cyberPurple.tokens == DesignTokens.cyberPurple)
    }
}
