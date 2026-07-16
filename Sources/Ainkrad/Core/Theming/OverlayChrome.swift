import SwiftUI
import AppKit
import AinkradAppKit

/// Shared visual language for the summonable HUD overlays — Launcher,
/// Settings, App Store, Workspace Overview, Quit. Centralizing the backdrop
/// opacity and panel treatment here keeps them reading as one system even
/// though each panel's content differs.
enum OverlayChrome {
    /// Panel corner radius, shared by every overlay's outer frame.
    static let cornerRadius: CGFloat = AinkradRadius.panel
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
/// blurred background, chamfered clip, and the Cardinal HUD edge-ring +
/// panel glow. Applied to each overlay's outermost panel container. Reads
/// the overlay opacity/blur settings live.
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
            .clipShape(ChamferShape(cut: OverlayChrome.cornerRadius))
            .ainkradEdgeRing(radius: OverlayChrome.cornerRadius)
            .ainkradPanelGlow()
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
