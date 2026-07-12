import SwiftUI
import AppKit

/// Shared visual language for the summonable HUD overlays — Launcher,
/// Settings, App Store, Workspace Overview, Quit. Centralizing the backdrop
/// opacity and panel treatment here keeps them reading as one system even
/// though each panel's content differs.
enum OverlayChrome {
    /// Panel corner radius, shared by every overlay's outer frame.
    static let cornerRadius: CGFloat = 14
    /// Opacity of the dimming scrim behind a summoned overlay.
    static let backdropOpacity: Double = 0.42
    /// Default panel background opacity (overridable in Settings → Appearance).
    static let backgroundOpacity: Double = 0.94
}

/// A frosted-glass blur that blurs the app content behind the panel — used as
/// the overlay panel backing when "background blur" is enabled in Settings.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// The shared panel finish: a (settings-driven) translucent + optionally
/// blurred background, rounded clip, a top-to-bottom gradient border stroke,
/// and the two-layer glow/contact shadow. Applied to each overlay's outermost
/// panel container. Reads the overlay opacity/blur settings live.
private struct HUDPanelChrome: ViewModifier {
    let tokens: DesignTokens
    @Environment(AppEnvironment.self) private var environment

    func body(content: Content) -> some View {
        let store = environment.generalSettingsStore
        content
            .background {
                ZStack {
                    if store.overlayBlurEnabled {
                        VisualEffectBlur()
                    }
                    tokens.background.opacity(store.overlayBackgroundOpacity)
                }
            }
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
    /// shadow stack) used by the Launcher, Settings, App Store, Workspace
    /// Overview, and Quit panels.
    func hudPanelChrome(tokens: DesignTokens) -> some View {
        modifier(HUDPanelChrome(tokens: tokens))
    }
}
