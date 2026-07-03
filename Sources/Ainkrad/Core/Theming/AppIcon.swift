/// The user's Dock-icon preference, decoupled from the theme: `auto` follows
/// the active theme, while `blue`/`purple` pin an explicit icon that a later
/// theme change does not override. Persisted in `GlobalSettings`.
enum AppIconChoice: String, Codable, CaseIterable {
    case auto
    case blue
    case purple

    /// The concrete icon this choice resolves to for a given theme.
    func resolvedIcon(for theme: Theme) -> AppIcon {
        switch self {
        case .auto: return theme == .cyberPurple ? .purple : .blue
        case .blue: return .blue
        case .purple: return .purple
        }
    }
}

/// A concrete, shippable Dock-icon variant (the two M1 dark icons). The two
/// light-background variants remain future — see App Icon Variants.md.
enum AppIcon: String {
    case blue
    case purple

    /// The bundled asset-catalog image name for this icon.
    var assetName: String {
        switch self {
        case .blue: return "AppIcon-NeonBlue"
        case .purple: return "AppIcon-CyberPurple"
        }
    }
}
