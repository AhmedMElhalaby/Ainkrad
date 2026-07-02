/// The two brand themes shipped in Milestone 1. `neonBlue` is first and is
/// the default. See WorkShop/Ainkrad/06 Brand/Theme System.md.
enum Theme: String, Codable, CaseIterable {
    case neonBlue
    case cyberPurple

    var tokens: DesignTokens {
        switch self {
        case .neonBlue: return .neonBlue
        case .cyberPurple: return .cyberPurple
        }
    }
}
