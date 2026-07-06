import Testing
import SwiftUI
import AppKit
@testable import Ainkrad

/// `IslandPalette.colors(for:)` is the one pure piece of the Living Island
/// (AIN-107/AIN-152) — everything else needs a running SceneKit renderer to
/// observe. Family checks extract plain sRGB components (same approach as
/// `Color.hexString` elsewhere in the codebase) rather than asserting on
/// SceneKit types.
@Suite("IslandPalette")
struct IslandPaletteTests {
    @Test("neonBlue and nord light rigs read blue-ish (green ≥ red, both below blue)")
    func blueFamilyThemesAreBlueIsh() {
        for theme in [Theme.neonBlue, .nord] {
            let components = rgb(IslandPalette.colors(for: theme).primary)
            #expect(components.green >= components.red, "\(theme) primary should not skew red-over-green")
            #expect(components.blue >= components.green, "\(theme) primary should be blue-dominant")
        }
    }

    @Test("cyberPurple and dracula light rigs read purple-ish (red > green, blue high)")
    func purpleFamilyThemesArePurpleIsh() {
        for theme in [Theme.cyberPurple, .dracula] {
            let components = rgb(IslandPalette.colors(for: theme).primary)
            #expect(components.red > components.green, "\(theme) primary should skew red-over-green (violet)")
            #expect(components.blue > components.green, "\(theme) primary should stay blue-leaning, not warm")
        }
    }

    @Test("colors(for:) is total: every theme resolves to a non-degenerate pair")
    func totalOverAllThemeCases() {
        for theme in Theme.allCases {
            let colors = IslandPalette.colors(for: theme)
            // Every theme's DesignTokens defines distinct accentPrimary /
            // accentSecondary hexes, so the two lights should never collapse
            // to the same color — a real signal something is mismapped.
            #expect(colors.primary != colors.secondary, "\(theme) should have distinct primary/secondary lights")
        }
    }

    @Test("colors(for:) matches the theme's own design tokens exactly")
    func matchesDesignTokens() {
        for theme in Theme.allCases {
            let colors = IslandPalette.colors(for: theme)
            #expect(colors.primary == theme.tokens.accentPrimary)
            #expect(colors.secondary == theme.tokens.accentSecondary)
        }
    }

    /// Plain sRGB components (0...1) for a `Color`, extracted the same way
    /// `Color.hexString` does — pure math, no renderer involved.
    private func rgb(_ color: Color) -> (red: Double, green: Double, blue: Double) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return (Double(resolved.redComponent), Double(resolved.greenComponent), Double(resolved.blueComponent))
    }
}
