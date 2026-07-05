/// The app themes. `neonBlue` is first and is the default. The original two
/// (Neon Blue, Cyber Purple) are the brand themes; the rest are well-known
/// palettes ported to full app themes (they drive both the app UI and the
/// terminal's Match-Theme colors). See UI Style Guidelines.
enum Theme: String, Codable, CaseIterable {
    case neonBlue
    case cyberPurple
    case dracula
    case nord
    case tokyoNight
    case gruvbox
    case solarizedDark

    var tokens: DesignTokens {
        switch self {
        case .neonBlue: return .neonBlue
        case .cyberPurple: return .cyberPurple
        case .dracula: return .dracula
        case .nord: return .nord
        case .tokyoNight: return .tokyoNight
        case .gruvbox: return .gruvbox
        case .solarizedDark: return .solarizedDark
        }
    }

    /// Human-readable name for the theme picker.
    var displayName: String {
        switch self {
        case .neonBlue: return "Neon Blue"
        case .cyberPurple: return "Cyber Purple"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .tokyoNight: return "Tokyo Night"
        case .gruvbox: return "Gruvbox"
        case .solarizedDark: return "Solarized Dark"
        }
    }

    /// Which app-icon color family this theme uses when the App Icon color is
    /// set to Auto. See App Icon Picker v2 — Design.
    var iconColorFamily: AppIconColor {
        switch self {
        case .cyberPurple, .dracula: return .purple
        case .neonBlue, .nord, .tokyoNight, .gruvbox, .solarizedDark: return .blue
        }
    }
}
