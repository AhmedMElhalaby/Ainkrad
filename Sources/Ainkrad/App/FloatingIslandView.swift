import SwiftUI

/// The floating-island hero artwork at the center of an empty workspace
/// (AIN-107, "Living Island"). This restores the original static 2D
/// artwork — a procedural SceneKit scene was tried and rejected as looking
/// worse than the flat image — and layers tasteful, ambient SwiftUI motion
/// on top: a pronounced vertical hover, a slow drifting sway, a breathing
/// scale, a pulsing glow tinted with the current theme's accent color, a
/// depth-displacement parallax driven by pointer position + slow idle
/// drift + workspace-switch banking, drifting particles, and a reactive
/// energy ring/flare sourced from `IslandState`. The artwork itself is
/// never cropped, recolored, or replaced — only its presentation moves.
///
/// Reduce Motion collapses all of this back to the plain static image with
/// no hover, sway, breathing, glow, parallax, particles, or ring/flare —
/// exactly the original look.
///
/// `isVisible` gates all motion off (parallax, particles, ring/flare, and
/// the ambient loops keep animating but cost nothing extra to render) when
/// this island isn't the active workspace or an overlay covers it — see
/// `EmptyWorkspaceView.islandVisible`.
///
/// NOTE: Reduce Motion disables *all* island motion by design — it renders
/// the plain static image only, per Apple's accessibility guidance.
struct FloatingIslandView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the island is the one currently on screen — the active
    /// workspace with no overlay covering it. When false, the 60fps clock
    /// still receives ticks but bails immediately, so no @State changes and
    /// no shader/particle cost for a background or covered workspace.
    var isVisible: Bool = true

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
    /// Slow Lissajous phase driving the idle drift term of the parallax
    /// offset, advanced by the 60fps clock.
    @State private var idlePhase: Double = 0
    /// Rotation (degrees) of the energy ring, advanced by the 60fps clock.
    @State private var ringRotation: Double = 0

    private let maxHoverOffset: CGFloat = 18
    private let maxSwayDegrees: Double = 1.75
    private let maxDepthOffset: CGFloat = 18
    /// The artwork's native pixel aspect (1536×1024) — the container must
    /// match this so the depth shader's per-axis normalization lines up
    /// with the drawn content instead of any letterboxed margin.
    private let artworkAspect: CGFloat = 1536.0 / 1024.0

    /// 60fps clock driving idle drift, ring rotation, and `IslandState`
    /// decay — the only place any of this view's `@State` changes. `@State`
    /// so a single stable instance survives view re-creation.
    @State private var tickTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

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
    /// coordinates against the depth texture. `offset` is composed each
    /// frame from pointer position, idle drift, and workspace-switch
    /// banking — see `IslandParallaxMath.offset`.
    private func parallaxShader(offset: CGSize, size: CGSize, depthName: String) -> Shader {
        ShaderLibrary.default.islandParallax(
            .float2(Float(size.width), Float(size.height)),
            .image(Image(depthName)),
            .float2(Float(offset.width), Float(offset.height)),
            .float(0.5)
        )
    }

    /// The 1.5-aspect rectangle the artwork actually occupies inside `available`
    /// (matching `.aspectRatio(_:contentMode:.fit)`), so the depth shader's
    /// normalization and the ring/flare positions register to the drawn art
    /// rather than the letterboxed frame.
    private func fittedSize(in available: CGSize, aspect: CGFloat) -> CGSize {
        guard available.width > 0, available.height > 0 else { return available }
        if available.width / available.height > aspect {
            // Height-constrained: full height, narrower width.
            return CGSize(width: available.height * aspect, height: available.height)
        } else {
            // Width-constrained: full width, shorter height.
            return CGSize(width: available.width, height: available.width / aspect)
        }
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
            let content = fittedSize(in: proxy.size, aspect: artworkAspect)
            let idle = CGPoint(x: sin(idlePhase * 0.62), y: sin(idlePhase * 0.41 + 1.3))
            let offset = IslandParallaxMath.offset(
                pointerFraction: pointerFraction,
                idle: idle,
                banking: environment.islandState.banking,
                maxOffset: maxDepthOffset
            )

            ZStack {
                glow
                artwork
                    .layerEffect(
                        parallaxShader(offset: offset, size: content, depthName: depthImageName),
                        maxSampleOffset: CGSize(width: 24, height: 24),
                        isEnabled: !reduceMotion && isVisible
                    )
                IslandParticleField(tint: glowColor, parallax: offset, isActive: !reduceMotion && isVisible)
                    .allowsHitTesting(false)
                energyRing(in: content)
                if let flarePhase = environment.islandState.flarePhase {
                    flare(phase: flarePhase, in: content)
                }
            }
            .aspectRatio(artworkAspect, contentMode: .fit)
            .offset(y: isHovering ? -maxHoverOffset : maxHoverOffset)
            .scaleEffect(isBreathing ? 1.03 : 1.0)
            .rotationEffect(.degrees(isSwaying ? maxSwayDegrees : -maxSwayDegrees))
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
            .onReceive(tickTimer) { _ in
                guard isVisible && !reduceMotion else { return }
                let dt = 1.0 / 60.0
                idlePhase += dt
                ringRotation += dt * 6
                environment.islandState.tick(dt: dt)
            }
            .onChange(of: environment.isLauncherPresented) { _, open in
                environment.islandState.launcherActive(open)
            }
            .onChange(of: environment.workspaceManager.activeWorkspaceID) { old, new in
                let ids = environment.workspaceManager.workspaces.map(\.id)
                guard let oldIndex = ids.firstIndex(of: old), let newIndex = ids.firstIndex(of: new) else { return }
                let direction = (newIndex > oldIndex) ? 1.0 : (newIndex < oldIndex ? -1.0 : 0.0)
                environment.islandState.bank(direction)
            }
        }
    }

    /// A faint, rotating ring of ambient energy over the citadel's painted
    /// ring motif — a screen-blended accent stroke whose opacity tracks
    /// `IslandState.ringIntensity` (idle glow, busy work, or the Launcher
    /// being open). Deliberately subtle: this reads as atmosphere, not a
    /// HUD dial.
    private func energyRing(in size: CGSize) -> some View {
        let diameter = size.width * 0.42
        return Circle()
            .strokeBorder(glowColor, lineWidth: 1.4)
            .frame(width: diameter, height: diameter)
            .position(x: size.width / 2, y: size.height * 0.42)
            .rotationEffect(.degrees(ringRotation))
            .opacity(0.10 + environment.islandState.ringIntensity * 0.22)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    /// A soft, screen-blended beam near the spire tip that brightens and
    /// fades across a `flarePhase` progression (0...1) — the one-shot
    /// notification "beacon" beat.
    private func flare(phase: Double, in size: CGSize) -> some View {
        let intensity = sin(min(max(phase, 0), 1) * .pi)
        return LinearGradient(
            colors: [glowColor.opacity(intensity * 0.55), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: size.width * 0.12, height: size.height * 0.5)
        .position(x: size.width / 2, y: size.height * 0.12)
        .blendMode(.screen)
        .allowsHitTesting(false)
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
