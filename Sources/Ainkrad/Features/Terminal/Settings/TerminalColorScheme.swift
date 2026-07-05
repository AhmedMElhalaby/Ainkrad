/// The terminal colors a theme's "Match App Theme" scheme renders with — the
/// terminal counterpart of the app's `DesignTokens`.
struct TerminalPalette {
    let background: String
    let foreground: String
    let cursor: String
    let ansi: [String]
}

/// The curated Match-Theme terminal palette for each app theme, keyed by the
/// theme's stable id (`HostThemeTokens.themeID`, which is the host `Theme`
/// rawValue). Terminal owns this table so it depends only on the SDK theme id,
/// not the host `Theme` enum. Unknown ids fall back to the default theme.
enum TerminalMatchThemePalette {
    static func forThemeID(_ id: String) -> TerminalPalette {
        table[id] ?? table["neonBlue"]!
    }

    private static let table: [String: TerminalPalette] = [
        "neonBlue":      TerminalPalette(background: "0A0E17", foreground: "E2E8F0", cursor: "22D3EE", ansi: TerminalColorScheme.matchTheme.ansi),
        "cyberPurple":   TerminalPalette(background: "080814", foreground: "EDE9FE", cursor: "C084FC", ansi: TerminalColorScheme.matchTheme.ansi),
        "dracula":       TerminalPalette(background: "282A36", foreground: "F8F8F2", cursor: "BD93F9", ansi: TerminalColorScheme.dracula.ansi),
        "nord":          TerminalPalette(background: "2E3440", foreground: "D8DEE9", cursor: "88C0D0", ansi: TerminalColorScheme.nord.ansi),
        "tokyoNight":    TerminalPalette(background: "1A1B26", foreground: "C0CAF5", cursor: "7AA2F7", ansi: TerminalColorScheme.tokyoNight.ansi),
        "gruvbox":       TerminalPalette(background: "282828", foreground: "EBDBB2", cursor: "FE8019", ansi: TerminalColorScheme.gruvbox.ansi),
        "solarizedDark": TerminalPalette(background: "002B36", foreground: "839496", cursor: "93A1A1", ansi: TerminalColorScheme.solarizedDark.ansi),
    ]
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

    static let all: [TerminalColorScheme] = [
        matchTheme, dracula, nord, tokyoNight, gruvbox, solarizedDark, monokai, oneDark, catppuccinMocha,
    ]

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

    static let nord = TerminalColorScheme(
        id: "nord",
        name: "Nord",
        background: "2E3440",
        foreground: "D8DEE9",
        cursor: "88C0D0",
        ansi: [
            "3B4252", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "88C0D0", "E5E9F0",
            "4C566A", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "8FBCBB", "ECEFF4",
        ]
    )

    static let tokyoNight = TerminalColorScheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        background: "1A1B26",
        foreground: "C0CAF5",
        cursor: "7AA2F7",
        ansi: [
            "15161E", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "A9B1D6",
            "414868", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "C0CAF5",
        ]
    )

    static let gruvbox = TerminalColorScheme(
        id: "gruvbox",
        name: "Gruvbox",
        background: "282828",
        foreground: "EBDBB2",
        cursor: "FE8019",
        ansi: [
            "282828", "CC241D", "98971A", "D79921", "458588", "B16286", "689D6A", "A89984",
            "928374", "FB4934", "B8BB26", "FABD2F", "83A598", "D3869B", "8EC07C", "EBDBB2",
        ]
    )

    static let monokai = TerminalColorScheme(
        id: "monokai",
        name: "Monokai",
        background: "272822",
        foreground: "F8F8F2",
        cursor: "F8F8F0",
        ansi: [
            "272822", "F92672", "A6E22E", "F4BF75", "66D9EF", "AE81FF", "A1EFE4", "F8F8F2",
            "75715E", "F92672", "A6E22E", "F4BF75", "66D9EF", "AE81FF", "A1EFE4", "F9F8F5",
        ]
    )

    static let oneDark = TerminalColorScheme(
        id: "one-dark",
        name: "One Dark",
        background: "282C34",
        foreground: "ABB2BF",
        cursor: "528BFF",
        ansi: [
            "282C34", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "ABB2BF",
            "5C6370", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "FFFFFF",
        ]
    )

    static let catppuccinMocha = TerminalColorScheme(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        background: "1E1E2E",
        foreground: "CDD6F4",
        cursor: "F5E0DC",
        ansi: [
            "45475A", "F38BA8", "A6E3A1", "F9E2AF", "89B4FA", "F5C2E7", "94E2D5", "BAC2DE",
            "585B70", "F38BA8", "A6E3A1", "F9E2AF", "89B4FA", "F5C2E7", "94E2D5", "A6ADC8",
        ]
    )
}
