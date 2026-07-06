import SwiftUI

/// The floating-island hero artwork at the center of an empty workspace
/// (AIN-107, "Living Island"). This restores the original static 2D
/// artwork — a procedural SceneKit scene was tried and rejected as looking
/// worse than the flat image — and layers tasteful, ambient SwiftUI motion
/// on top: a pronounced vertical hover, a slow drifting sway, a breathing
/// scale, a pulsing glow tinted with the current theme's accent color, and
/// a snappy pointer-driven 3D parallax/tilt. The artwork itself is never
/// cropped, recolored, or replaced — only its presentation moves.
///
/// Reduce Motion collapses all of this back to the plain static image with
/// no hover, sway, tilt, breathing, or glow — exactly the original look.
///
/// NOTE: Reduce Motion disables *all* island motion by design (ambient hover,
/// sway, breathing, glow pulse, and pointer parallax) — it renders the plain
/// static image only, per Apple's accessibility guidance.
struct FloatingIslandView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vertical hover, amplified so it reads clearly without hovering.
    @State private var isHovering = false
    /// Slow ±~1.75° drift rotation, phase-offset from the hover loop so the
    /// island feels like it's adrift rather than mechanically bobbing.
    @State private var isSwaying = false
    /// Gentle "breathing" scale, phase-offset from the hover so the loops
    /// don't feel mechanically locked together.
    @State private var isBreathing = false
    /// Opacity pulse on the glow layer behind the artwork.
    @State private var isGlowing = false
    /// Pointer position, normalized to -1...1 from center, used for the
    /// parallax tilt. Zero when the pointer isn't over the island.
    @State private var pointerFraction: CGPoint = .zero

    private let maxTiltDegrees: Double = 11
    private let maxParallaxOffset: CGFloat = 12
    private let maxHoverOffset: CGFloat = 18
    private let maxSwayDegrees: Double = 1.75

    private var imageName: String {
        switch environment.themeManager.currentTheme {
        case .cyberPurple, .dracula, .tokyoNight: return "Island-CyberPurple"
        default: return "Island-NeonBlue"
        }
    }

    /// Per-theme depth map for the 2.5D parallax shader (white = near,
    /// black = far), matching `imageName`'s theme grouping.
    private var depthImageName: String {
        switch environment.themeManager.currentTheme {
        case .cyberPurple, .dracula, .tokyoNight: return "Island-CyberPurple-Depth"
        default: return "Island-NeonBlue-Depth"
        }
    }

    private var glowColor: Color {
        environment.themeManager.tokens.accentPrimary
    }

    /// Builds the depth-displacement shader for the artwork layer. `offset`
    /// is the max per-axis displacement (in layer points); `size` must be
    /// the artwork's own layout size so the shader can normalize sample
    /// coordinates against the depth texture.
    ///
    /// NOTE: `offset` is a fixed placeholder for now — a later task drives
    /// it from ambient motion and pointer position.
    private func parallaxShader(offset: CGSize, size: CGSize, depthName: String) -> Shader {
        ShaderLibrary.default.islandParallax(
            .float2(Float(size.width), Float(size.height)),
            .image(Image(depthName)),
            .float2(Float(offset.width), Float(offset.height)),
            .float(0.5)
        )
    }

    var body: some View {
        if reduceMotion {
            artwork
        } else {
            interactiveIsland
        }
    }

    private var artwork: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
    }

    private var interactiveIsland: some View {
        GeometryReader { proxy in
            ZStack {
                glow
                artwork
                    .layerEffect(
                        parallaxShader(
                            offset: CGSize(width: 10, height: 6),
                            size: proxy.size,
                            depthName: depthImageName
                        ),
                        maxSampleOffset: CGSize(width: 24, height: 24),
                        isEnabled: !reduceMotion
                    )
            }
            .offset(
                x: pointerFraction.x * -maxParallaxOffset,
                y: (pointerFraction.y * -maxParallaxOffset) + (isHovering ? -maxHoverOffset : maxHoverOffset)
            )
            .scaleEffect(isBreathing ? 1.03 : 1.0)
            .rotationEffect(.degrees(isSwaying ? maxSwayDegrees : -maxSwayDegrees))
            .rotation3DEffect(
                .degrees(pointerFraction.y * -maxTiltDegrees),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.5
            )
            .rotation3DEffect(
                .degrees(pointerFraction.x * maxTiltDegrees),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pointerFraction)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    let width = max(proxy.size.width, 1)
                    let height = max(proxy.size.height, 1)
                    pointerFraction = CGPoint(
                        x: min(max((location.x / width) * 2 - 1, -1), 1),
                        y: min(max((location.y / height) * 2 - 1, -1), 1)
                    )
                case .ended:
                    withAnimation(.easeOut(duration: 0.35)) {
                        pointerFraction = .zero
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear(perform: startAmbientMotion)
        }
    }

    /// A blurred, accent-tinted copy of the artwork sitting behind the real
    /// image, pulsing at a clearly visible opacity — a soft aura, not a
    /// light source. Kept accent-tinted so it reads as ambient, not gaudy.
    private var glow: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .blur(radius: 42)
            .colorMultiply(glowColor)
            .opacity(isGlowing ? 0.5 : 0.2)
            .allowsHitTesting(false)
    }

    private func startAmbientMotion() {
        withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
            isHovering = true
        }
        withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true).delay(2)) {
            isSwaying = true
        }
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true).delay(1.5)) {
            isBreathing = true
        }
        withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true).delay(0.75)) {
            isGlowing = true
        }
    }
}
