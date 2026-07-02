import SwiftUI

/// Semantic color tokens for one theme. Views read these — never a raw hex
/// literal — so a view is automatically correct in both themes. See
/// WorkShop/Ainkrad/06 Brand/Color Tokens.md for the source values.
struct DesignTokens: Equatable {
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let accentPrimary: Color
    let accentSecondary: Color
    let accentTertiary: Color
    let foreground: Color

    static let neonBlue = DesignTokens(
        background: Color(hex: "0A0E17"),
        surface: Color(hex: "111827"),
        surfaceElevated: Color(hex: "1A2233"),
        accentPrimary: Color(hex: "2563EB"),
        accentSecondary: Color(hex: "22D3EE"),
        accentTertiary: Color(hex: "10B981"),
        foreground: Color(hex: "E2E8F0")
    )

    static let cyberPurple = DesignTokens(
        background: Color(hex: "080814"),
        surface: Color(hex: "141420"),
        surfaceElevated: Color(hex: "1F182E"),
        accentPrimary: Color(hex: "7C1AED"),
        accentSecondary: Color(hex: "C084FC"),
        accentTertiary: Color(hex: "EC4899"),
        foreground: Color(hex: "EDE9FE")
    )
}
