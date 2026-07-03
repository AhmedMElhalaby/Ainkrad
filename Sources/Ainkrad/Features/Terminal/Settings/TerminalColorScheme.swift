/// The terminal colors a theme's "Match App Theme" scheme renders with — the
/// terminal counterpart of the app's `DesignTokens`.
struct TerminalPalette {
    let background: String
    let foreground: String
    let cursor: String
    let ansi: [String]
}

extension Theme {
    /// The terminal palette for this theme's Match-Theme scheme. Extended as
    /// new themes are added (see the themes work).
    var terminalPalette: TerminalPalette {
        switch self {
        case .neonBlue:
            return TerminalPalette(background: "0A0E17", foreground: "E2E8F0", cursor: "22D3EE", ansi: TerminalColorScheme.matchTheme.ansi)
        case .cyberPurple:
            return TerminalPalette(background: "080814", foreground: "EDE9FE", cursor: "C084FC", ansi: TerminalColorScheme.matchTheme.ansi)
        }
    }
}

/// A selectable terminal color scheme. `background`/`foreground`/`cursor` are
/// hex strings, or `nil` for the special "Match App Theme" scheme which
/// derives them from the active app theme. `ansi` is always the full 16-color
/// palette (8 normal + 8 bright). See Terminal App Architecture.md.
struct TerminalColorScheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: String?
    let foreground: String?
    let cursor: String?
    let ansi: [String]

    static let matchThemeID = "match-theme"

    static let all: [TerminalColorScheme] = [matchTheme, dracula, solarizedDark]

    /// The scheme for an id, falling back to Match Theme for unknown ids.
    static func scheme(id: String) -> TerminalColorScheme {
        all.first { $0.id == id } ?? matchTheme
    }

    /// Colors follow the app theme; the ANSI palette is a neutral default.
    static let matchTheme = TerminalColorScheme(
        id: matchThemeID,
        name: "Match App Theme",
        background: nil,
        foreground: nil,
        cursor: nil,
        ansi: [
            "1A1D24", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "ABB2BF",
            "5C6370", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "FFFFFF",
        ]
    )

    static let dracula = TerminalColorScheme(
        id: "dracula",
        name: "Dracula",
        background: "282A36",
        foreground: "F8F8F2",
        cursor: "BD93F9",
        ansi: [
            "21222C", "FF5555", "50FA7B", "F1FA8C", "BD93F9", "FF79C6", "8BE9FD", "F8F8F2",
            "6272A4", "FF6E6E", "69FF94", "FFFFA5", "D6ACFF", "FF92DF", "A4FFFF", "FFFFFF",
        ]
    )

    static let solarizedDark = TerminalColorScheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        background: "002B36",
        foreground: "839496",
        cursor: "93A1A1",
        ansi: [
            "073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5",
            "002B36", "CB4B16", "586E75", "657B83", "839496", "6C71C4", "93A1A1", "FDF6E3",
        ]
    )
}
