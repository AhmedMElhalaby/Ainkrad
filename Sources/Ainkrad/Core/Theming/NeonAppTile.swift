import SwiftUI

/// The neon app-tile shown in the Launcher, Workspace overview, tile-mode chips,
/// the Block header, and Settings rows. Drawn live from the active theme's
/// `DesignTokens`, so the glyph and its glow follow whatever theme is current —
/// at any size and for any app (its SF Symbol) — with no baked per-theme art.
///
/// Replaces the former per-theme `AppTile-<id>-<theme>` PNG assets: a dark
/// top-lit rounded tile with the app's SF Symbol in the secondary accent and a
/// soft two-layer neon bloom.
struct NeonAppTile: View {
    /// The app's SF Symbol name (its `AinkradApp.icon`).
    let symbol: String
    let tokens: DesignTokens
    var size: CGFloat = 32

    var body: some View {
        let inset = size * 0.0625
        let tile = size - inset * 2
        let radius = tile * 0.235
        // Glow/stroke are authored at a 224pt tile; scale to the render size so
        // the bloom reads the same whether drawn at 18pt or 34pt.
        let s = tile / 224

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [tokens.surfaceElevated, tokens.background],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: tile, height: tile)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.14),
                                                    .white.opacity(0.02),
                                                    .clear],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: max(0.5, 1.2 * s))
                )
                .shadow(color: .black.opacity(0.45), radius: 12 * s, x: 0, y: 6 * s)

            Image(systemName: symbol)
                .font(.system(size: tile * 0.42, weight: .medium))
                .foregroundStyle(tokens.accentSecondary)
                .shadow(color: tokens.accentSecondary.opacity(0.45), radius: 4 * s)
                .shadow(color: tokens.accentSecondary.opacity(0.22), radius: 10 * s)
        }
        .frame(width: size, height: size)
    }
}
