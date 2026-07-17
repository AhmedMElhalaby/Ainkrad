import SwiftUI

/// The neon app-icon shown in the Launcher, Workspace overview, tile-mode chips,
/// the Block header, App Store, and Settings rows. Drawn live from the active
/// theme's `DesignTokens`, so the glyph and its glow follow whatever theme is
/// current — at any size and for any app (its SF Symbol) — with no baked
/// per-theme art.
///
/// The glyph sits on a TRANSPARENT background (no dark tile) and is sized to
/// nearly fill the frame, in the secondary accent with a soft two-layer neon
/// bloom.
struct NeonAppTile: View {
    /// The app's SF Symbol name (its `AinkradApp.icon`).
    let symbol: String
    let tokens: DesignTokens
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.82, weight: .medium))
            .foregroundStyle(tokens.accentSecondary)
            // Glow scales with the render size so the bloom reads the same at
            // 18pt or 88pt — kept subtle.
            .shadow(color: tokens.accentSecondary.opacity(0.35), radius: size * 0.09)
            .shadow(color: tokens.accentSecondary.opacity(0.16), radius: size * 0.22)
            .frame(width: size, height: size)
    }
}
