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
