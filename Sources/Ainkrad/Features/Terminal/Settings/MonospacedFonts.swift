import AppKit

/// The list of monospaced font families offered in Terminal settings: every
/// installed fixed-pitch family, unioned with the fonts Ainkrad bundles
/// (JetBrains Mono, MesloLGS NF) so they are always present even if the
/// availability probe misses them.
enum MonospacedFonts {
    /// Families Ainkrad bundles or always wants offered when present.
    private static let preferred = ["MesloLGS NF", "JetBrains Mono", "Menlo", "Monaco"]

    @MainActor
    static func available() -> [String] {
        var families = Set<String>()

        for family in preferred where NSFont(name: family, size: 12) != nil {
            families.insert(family)
        }

        for family in NSFontManager.shared.availableFontFamilies {
            if let font = NSFont(name: family, size: 12), font.isFixedPitch {
                families.insert(family)
            }
        }

        return families.sorted()
    }
}
