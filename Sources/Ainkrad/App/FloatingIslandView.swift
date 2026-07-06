import SwiftUI
import AppKit

/// The floating-island hero artwork at the center of an empty workspace —
/// a real-time procedural 3D scene rendered with SceneKit (AIN-107, "Living
/// Island"), in the same view slot the original static 2D artwork used to
/// occupy. The scene renders with a transparent background, so
/// `AmbientSkyView`'s sky shows through it exactly as it did behind the old
/// artwork. Reduce Motion freezes the orbit/parallax/particles to a single
/// static frame (AIN-153); the render loop itself pauses whenever the
/// window is occluded, miniaturized, or off-screen, so the island costs
/// nothing when it isn't visible. Re-lights per theme via `IslandPalette`
/// (AIN-152) — one scene serves every theme, no rebuild.
///
/// If SceneKit is ever unavailable in the running environment, this falls
/// back to the original static artwork rather than risk a crash — the
/// island is ambience, never a requirement.
struct FloatingIslandView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointerFraction: CGPoint = .zero

    private var imageName: String {
        // Island art ships in two accents; new themes use the nearer one.
        switch environment.themeManager.currentTheme {
        case .cyberPurple, .dracula, .tokyoNight: return "Island-CyberPurple"
        default: return "Island-NeonBlue"
        }
    }

    /// `IslandPalette.colors(for:)` maps the theme's own tokens; this folds
    /// in a user's custom accent-color override (AIN-143, only visible via
    /// `ThemeManager.tokens`) on top of it, so the island's primary light
    /// matches whatever accent the rest of the UI is actually showing.
    private var islandColors: IslandPalette.LightColors {
        let themed = IslandPalette.colors(for: environment.themeManager.currentTheme)
        let tokens = environment.themeManager.tokens
        return IslandPalette.LightColors(primary: tokens.accentPrimary, secondary: themed.secondary)
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if NSClassFromString("SCNView") != nil {
                    IslandSceneView(
                        colors: islandColors,
                        reduceMotion: reduceMotion,
                        pointerFraction: pointerFraction
                    )
                } else {
                    fallbackImage
                }
            }
            .onContinuousHover { phase in
                guard !reduceMotion else { return }
                switch phase {
                case .active(let location):
                    let width = max(proxy.size.width, 1)
                    let height = max(proxy.size.height, 1)
                    pointerFraction = CGPoint(
                        x: (location.x / width) * 2 - 1,
                        y: (location.y / height) * 2 - 1
                    )
                case .ended:
                    pointerFraction = .zero
                }
            }
        }
    }

    private var fallbackImage: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
    }
}
