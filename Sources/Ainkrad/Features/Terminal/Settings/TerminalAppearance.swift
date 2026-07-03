/// The fully-resolved appearance a terminal renders with — the product of a
/// `TerminalColorScheme` and (for Match Theme) the active app theme, plus the
/// resolved font. All colors are hex strings; the view layer converts them to
/// `NSColor` / SwiftTerm colors. `Equatable` so SwiftUI only re-applies when
/// something actually changed.
struct TerminalRenderAppearance: Equatable {
    let background: String
    let foreground: String
    let cursor: String
    let ansi: [String]
    let fontFamily: String
    let fontSize: Double
}

/// Pure resolution of `TerminalSettings` (+ the active theme) into a concrete
/// `TerminalRenderAppearance`. No AppKit here — kept unit-testable.
enum TerminalAppearanceResolver {
    static let defaultFontFamily = "MesloLGS NF"
    static let defaultFontSize: Double = 15

    static func resolve(settings: TerminalSettings, theme: Theme) -> TerminalRenderAppearance {
        let scheme = TerminalColorScheme.scheme(id: settings.colorSchemeID)
        let themed = themeColors(theme)
        return TerminalRenderAppearance(
            background: scheme.background ?? themed.background,
            foreground: scheme.foreground ?? themed.foreground,
            cursor: scheme.cursor ?? themed.cursor,
            ansi: scheme.ansi,
            fontFamily: settings.fontFamily ?? defaultFontFamily,
            fontSize: settings.fontSize ?? defaultFontSize
        )
    }

    /// The terminal bg/fg/cursor for "Match App Theme" — mirrors the theme's
    /// `DesignTokens` (background / foreground / accentSecondary).
    private static func themeColors(_ theme: Theme) -> (background: String, foreground: String, cursor: String) {
        switch theme {
        case .neonBlue: return ("0A0E17", "E2E8F0", "22D3EE")
        case .cyberPurple: return ("080814", "EDE9FE", "C084FC")
        }
    }
}
