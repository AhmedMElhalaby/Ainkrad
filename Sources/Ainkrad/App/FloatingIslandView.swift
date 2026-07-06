import SwiftUI

/// The floating-island hero artwork at the center of an empty workspace
/// (AIN-107, "Living Island"). This restores the original static 2D
/// artwork — a procedural SceneKit scene was tried and rejected as looking
/// worse than the flat image — and layers tasteful, ambient SwiftUI motion
/// on top: a slow vertical hover, a gentle breathing scale, a soft pulsing
/// glow tinted with the current theme's accent color, and subtle
/// pointer-driven 3D parallax/tilt. The artwork itself is never cropped,
/// recolored, or replaced — only its presentation moves.
///
/// Reduce Motion collapses all of this back to the plain static image with
/// no hover, tilt, breathing, or glow — exactly the original look.
struct FloatingIslandView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Slow vertical hover, matching the original artwork's motion.
    @State private var isHovering = false
    /// Very gentle "breathing" scale, phase-offset from the hover so the
    /// two loops don't feel mechanically locked together.
    @State private var isBreathing = false
    /// Slow opacity pulse on the glow layer behind the artwork.
    @State private var isGlowing = false
    /// Pointer position, normalized to -1...1 from center, used for the
    /// parallax tilt. Zero when the pointer isn't over the island.
    @State private var pointerFraction: CGPoint = .zero

    private let maxTiltDegrees: Double = 6
    private let maxParallaxOffset: CGFloat = 5

    private var imageName: String {
        switch environment.themeManager.currentTheme {
        case .cyberPurple, .dracula, .tokyoNight: return "Island-CyberPurple"
        default: return "Island-NeonBlue"
        }
    }

    private var glowColor: Color {
        environment.themeManager.tokens.accentPrimary
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
            }
            .offset(
                x: pointerFraction.x * -maxParallaxOffset,
                y: (pointerFraction.y * -maxParallaxOffset) + (isHovering ? -9 : 9)
            )
            .scaleEffect(isBreathing ? 1.015 : 1.0)
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
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: pointerFraction)
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
                    withAnimation(.easeOut(duration: 0.4)) {
                        pointerFraction = .zero
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear(perform: startAmbientMotion)
        }
    }

    /// A blurred, accent-tinted copy of the artwork sitting behind the real
    /// image, pulsing slowly at low opacity — a soft glow, not a light
    /// source. Kept understated: the artwork stays the star.
    private var glow: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .blur(radius: 36)
            .colorMultiply(glowColor)
            .opacity(isGlowing ? 0.35 : 0.15)
            .allowsHitTesting(false)
    }

    private func startAmbientMotion() {
        withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
            isHovering = true
        }
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true).delay(1.5)) {
            isBreathing = true
        }
        withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true).delay(0.75)) {
            isGlowing = true
        }
    }
}
