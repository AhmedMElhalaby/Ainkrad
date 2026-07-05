import SwiftUI
import AinkradAppKit

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

    // Well-known palettes ported to full app themes (each also drives the
    // terminal's Match-Theme colors — see TerminalMatchThemePalette).

    static let dracula = DesignTokens(
        background: Color(hex: "282A36"),
        surface: Color(hex: "343746"),
        surfaceElevated: Color(hex: "424458"),
        accentPrimary: Color(hex: "BD93F9"),
        accentSecondary: Color(hex: "FF79C6"),
        accentTertiary: Color(hex: "8BE9FD"),
        foreground: Color(hex: "F8F8F2")
    )

    static let nord = DesignTokens(
        background: Color(hex: "2E3440"),
        surface: Color(hex: "3B4252"),
        surfaceElevated: Color(hex: "434C5E"),
        accentPrimary: Color(hex: "88C0D0"),
        accentSecondary: Color(hex: "81A1C1"),
        accentTertiary: Color(hex: "A3BE8C"),
        foreground: Color(hex: "ECEFF4")
    )

    static let tokyoNight = DesignTokens(
        background: Color(hex: "1A1B26"),
        surface: Color(hex: "24283B"),
        surfaceElevated: Color(hex: "2F3549"),
        accentPrimary: Color(hex: "7AA2F7"),
        accentSecondary: Color(hex: "BB9AF7"),
        accentTertiary: Color(hex: "7DCFFF"),
        foreground: Color(hex: "C0CAF5")
    )

    static let gruvbox = DesignTokens(
        background: Color(hex: "282828"),
        surface: Color(hex: "3C3836"),
        surfaceElevated: Color(hex: "504945"),
        accentPrimary: Color(hex: "FE8019"),
        accentSecondary: Color(hex: "FABD2F"),
        accentTertiary: Color(hex: "B8BB26"),
        foreground: Color(hex: "EBDBB2")
    )

    static let solarizedDark = DesignTokens(
        background: Color(hex: "002B36"),
        surface: Color(hex: "073642"),
        surfaceElevated: Color(hex: "0A4451"),
        accentPrimary: Color(hex: "268BD2"),
        accentSecondary: Color(hex: "2AA198"),
        accentTertiary: Color(hex: "859900"),
        foreground: Color(hex: "93A1A1")
    )
}

extension DesignTokens {
    /// Bridges the SDK's `HostThemeTokens` snapshot back into host `DesignTokens`
    /// so shared Settings components (`SettingsSectionHeader`, `NeonToggle`) that
    /// take `DesignTokens` can be driven from a decoupled app's `host.theme`.
    /// The 7 color fields map one-to-one; `themeID` is not a color and is dropped.
    init(from t: HostThemeTokens) {
        self.init(
            background: t.background,
            surface: t.surface,
            surfaceElevated: t.surfaceElevated,
            accentPrimary: t.accentPrimary,
            accentSecondary: t.accentSecondary,
            accentTertiary: t.accentTertiary,
            foreground: t.foreground
        )
    }
}
