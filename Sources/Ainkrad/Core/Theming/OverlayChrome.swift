import SwiftUI

/// Shared visual language for the four summonable HUD overlays — Launcher,
/// Settings, Marketplace, Workspace Overview. Centralizing the backdrop
/// opacity and panel treatment here keeps them reading as one system even
/// though each panel's content differs.
enum OverlayChrome {
    /// Panel corner radius, shared by every overlay's outer frame.
    static let cornerRadius: CGFloat = 14
    /// Opacity of the dimming scrim behind a summoned overlay.
    static let backdropOpacity: Double = 0.42
    /// Opacity of the panel's tinted background fill.
    static let backgroundOpacity: Double = 0.94
}

/// The shared panel finish: tinted background, rounded clip, a top-to-bottom
/// gradient border stroke, and the two-layer glow/contact shadow. Applied to
/// each overlay's outermost panel container.
private struct HUDPanelChrome: ViewModifier {
    let tokens: DesignTokens

    func body(content: Content) -> some View {
        content
            .background(tokens.background.opacity(OverlayChrome.backgroundOpacity))
            .clipShape(RoundedRectangle(cornerRadius: OverlayChrome.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OverlayChrome.cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [tokens.accentSecondary.opacity(0.55), tokens.accentPrimary.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tokens.accentPrimary.opacity(0.35), radius: 42)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }
}

extension View {
    /// Applies the shared HUD panel finish (background, clip, border glow,
    /// shadow stack) used by the Launcher, Settings, Marketplace, and
    /// Workspace Overview panels.
    func hudPanelChrome(tokens: DesignTokens) -> some View {
        modifier(HUDPanelChrome(tokens: tokens))
    }
}
