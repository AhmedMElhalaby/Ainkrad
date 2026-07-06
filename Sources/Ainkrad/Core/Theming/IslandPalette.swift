import SwiftUI

/// Maps each theme to the light/emissive colors that re-light the Living
/// Island (AIN-107/AIN-152) — the spire-window point light, the arch-ring
/// glow, and the ember particle tint. Pure: no SceneKit types, so it's
/// plain-value testable without a running renderer. Every theme gets its own
/// distinct pair straight from `DesignTokens` (not just a coarse two-bucket
/// family) so all seven themes look distinctly re-lit, not just "blue vs
/// purple" — see `Theme.iconColorFamily` for that coarser precedent.
enum IslandPalette {
    /// The two accent-derived colors driving the island's light rig.
    struct LightColors: Equatable {
        /// Spire windows + the arch ring's primary glow.
        let primary: Color
        /// Ember particle tint + the ring's secondary emissive highlight.
        let secondary: Color
    }

    /// Total over every `Theme` case — always resolves via that theme's own
    /// `DesignTokens`, so there's no "missing" theme to fall back on.
    static func colors(for theme: Theme) -> LightColors {
        let tokens = theme.tokens
        return LightColors(primary: tokens.accentPrimary, secondary: tokens.accentSecondary)
    }
}
