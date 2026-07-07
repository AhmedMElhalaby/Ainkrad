// Sources/Ainkrad/App/FloatingIslandView.swift
import SwiftUI

/// The floating-island hero at the center of an empty workspace (AIN-107,
/// "Living Island"), v3: a layered composition of per-element sprites
/// (`IslandLayers`) over `AmbientSkyView` with no opaque background. Clouds
/// drift horizontally and islets bob (`IslandMotionMath`), the ring glows and
/// flares from `IslandState`, and the whole island banks slightly on
/// workspace switches. Purple-family themes get a runtime tint.
///
/// Reduce Motion renders the static composition (no drift/bob/flare/banking).
/// `isVisible` gates the 60 fps `IslandState` clock and the drift/bob timeline
/// so a covered or background workspace costs nothing.
struct FloatingIslandView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isVisible: Bool = true

    /// 60 fps clock; the only place `IslandState` advances.
    @State private var tickTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    /// Which interactive element the pointer is over (ring/chevron/logo/slogan).
    @State private var hovered: IslandLayer.Kind?

    /// The artwork's native pixel aspect (1536×1024).
    private let artworkAspect: CGFloat = 1536.0 / 1024.0
    private let maxBankOffset: CGFloat = 14

    private var isPurple: Bool {
        switch environment.themeManager.currentTheme {
        case .cyberPurple, .dracula, .tokyoNight: return true
        default: return false
        }
    }
    private var accent: Color { environment.themeManager.tokens.accentPrimary }

    var body: some View {
        GeometryReader { proxy in
            let rect = fittedRect(in: proxy.size)
            Group {
                if isVisible && !reduceMotion {
                    TimelineView(.animation) { context in
                        island(rect: rect, time: context.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    island(rect: rect, time: 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Hover: one stable transparent layer (not rebuilt by the per-frame
            // TimelineView) with a deterministic pointer hit-test. Extends below
            // the frame to cover the wordmark, which sits at cy > 1.
            .overlay {
                Color.white.opacity(0.001)
                    .frame(width: rect.width, height: rect.height * 1.3)
                    .position(x: rect.midX, y: rect.minY + rect.height * 0.65)
                    .onContinuousHover { phase in
                        let hit: IslandLayer.Kind?
                        switch phase {
                        case .active(let p): hit = hoverHit(p, rect: rect)
                        case .ended:         hit = nil
                        }
                        if hit != hovered {
                            withAnimation(.easeOut(duration: 0.2)) { hovered = hit }
                        }
                    }
            }
            .onReceive(tickTimer) { _ in
                guard isVisible && !reduceMotion else { return }
                environment.islandState.tick(dt: 1.0 / 60.0)
            }
            .onChange(of: environment.isLauncherPresented) { _, open in
                environment.islandState.launcherActive(open)
            }
            .onChange(of: isVisible) { _, vis in
                if !vis { hovered = nil }
            }
            .onChange(of: environment.workspaceManager.activeWorkspaceID) { old, new in
                guard !reduceMotion else { return }
                let ids = environment.workspaceManager.workspaces.map(\.id)
                guard let o = ids.firstIndex(of: old), let n = ids.firstIndex(of: new) else { return }
                environment.islandState.bank(n > o ? 1 : (n < o ? -1 : 0))
            }
        }
    }

    /// The 1.5-aspect rectangle the artwork occupies inside `available`
    /// (matching `.aspectRatio(_:contentMode:.fit)`), so normalized positions
    /// register to the drawn art rather than the letterboxed frame.
    private func fittedRect(in available: CGSize) -> CGRect {
        guard available.width > 0, available.height > 0 else { return .zero }
        let w: CGFloat, h: CGFloat
        if available.width / available.height > artworkAspect {
            h = available.height; w = h * artworkAspect
        } else {
            w = available.width; h = w / artworkAspect
        }
        return CGRect(x: (available.width - w) / 2, y: (available.height - h) / 2, width: w, height: h)
    }

    @ViewBuilder
    private func island(rect: CGRect, time: Double) -> some View {
        let animating = isVisible && !reduceMotion
        let bank = animating ? CGFloat(environment.islandState.banking) * maxBankOffset : 0
        ZStack {
            glow(rect: rect)
            ForEach(IslandLayers.sortedByZ) { layer in
                layerView(layer, rect: rect, time: time, animating: animating)
            }
            if animating, let phase = environment.islandState.flarePhase {
                flare(phase: phase, rect: rect)
            }
        }
        .offset(x: bank)
    }

    /// Which interactive element (if any) the pointer at local `p` is over.
    /// Coordinates are local to the hover layer, whose top-left aligns with the
    /// art rect origin. Wordmark rectangles take priority over the ring so the
    /// chevron wins where it overlaps the ring's lower band.
    private func hoverHit(_ p: CGPoint, rect: CGRect) -> IslandLayer.Kind? {
        for kind in [IslandLayer.Kind.chevron, .logo, .slogan] {
            guard let l = IslandLayers.all.first(where: { $0.kind == kind }) else { continue }
            let cx = rect.width * l.cx, cy = rect.height * l.cy
            let hw = rect.width * l.width / 2, hh = rect.height * hoverHeight(for: kind) / 2
            if abs(p.x - cx) <= hw && abs(p.y - cy) <= hh { return kind }
        }
        if let r = IslandLayers.all.first(where: { $0.kind == .ring }) {
            let cx = rect.width * r.cx, cy = rect.height * r.cy
            let rw = rect.width * r.width, rh = rw * (576.0 / 567.0)   // ring sprite aspect
            let nx = (p.x - cx) / (rw / 2), ny = (p.y - cy) / (rh / 2)
            let radius = (nx * nx + ny * ny).squareRoot()
            if radius >= 0.68 && radius <= 1.06 { return .ring }        // annulus band
        }
        return nil
    }

    /// Normalized hit-height per wordmark element (from extraction bboxes).
    private func hoverHeight(for kind: IslandLayer.Kind) -> Double {
        switch kind {
        case .chevron: return 0.1504
        case .logo:    return 0.0762
        case .slogan:  return 0.0254
        default:       return 0.05
        }
    }

    /// Localized soft blue radial glow behind the ring (no opaque bg).
    private func glow(rect: CGRect) -> AnyView {
        guard let ring = IslandLayers.all.first(where: { $0.kind == .ring }) else {
            return AnyView(EmptyView())
        }
        let intensity = environment.islandState.ringIntensity
        return AnyView(
            RadialGradient(
                colors: [accent.opacity(0.10 + intensity * 0.22), .clear],
                center: .center, startRadius: 0, endRadius: rect.width * 0.34
            )
            .frame(width: rect.width * 0.9, height: rect.width * 0.9)
            .position(x: rect.minX + rect.width * ring.cx, y: rect.minY + rect.height * ring.cy)
            .blendMode(.screen)
            .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private func layerView(_ layer: IslandLayer, rect: CGRect, time: Double, animating: Bool) -> some View {
        let w = rect.width * layer.width
        let px = rect.minX + rect.width * layer.cx
        let py = rect.minY + rect.height * layer.cy
        let dx: CGFloat = (animating && layer.kind == .cloud) ? IslandMotionMath.cloudDriftX(seed: layer.seed ?? 0, time: time) : 0
        let dy: CGFloat = (animating && layer.kind == .islet) ? IslandMotionMath.isletBobY(seed: layer.seed ?? 0, time: time) : 0
        Image(layer.id)
            .resizable()
            .scaledToFit()
            .frame(width: w)
            .colorMultiply(tint(for: layer))
            .brightness(layer.kind == .ring ? environment.islandState.ringIntensity * 0.12 : 0)
            .shadow(color: ringGlowColor(layer), radius: layer.kind == .ring ? 10 + environment.islandState.ringIntensity * 14 : 0)
            // Hover glow: brighten, scale up slightly, and stack two accent
            // blooms so it reads clearly even on the bright chevron / ring.
            .brightness(hovered == layer.kind ? 0.28 : 0)
            .shadow(color: hovered == layer.kind ? accent : .clear, radius: hovered == layer.kind ? 14 : 0)
            .shadow(color: hovered == layer.kind ? accent.opacity(0.85) : .clear, radius: hovered == layer.kind ? 30 : 0)
            .scaleEffect(hovered == layer.kind ? 1.06 : 1.0)
            .position(x: px, y: py)
            .offset(x: dx, y: dy)
            .allowsHitTesting(false)
    }

    /// Purple-family tint on the structure (citadel/ring); clouds/islets stay
    /// near-neutral so they don't turn muddy. `.white` = no change.
    private func tint(for layer: IslandLayer) -> Color {
        guard isPurple else { return .white }
        switch layer.kind {
        case .citadel, .ring, .chevron: return Color(red: 0.82, green: 0.72, blue: 1.0)
        default: return .white
        }
    }

    private func ringGlowColor(_ layer: IslandLayer) -> Color {
        layer.kind == .ring ? accent.opacity(0.35 + environment.islandState.ringIntensity * 0.4) : .clear
    }

    /// One-shot beacon beam near the spire tip (notifications).
    private func flare(phase: Double, rect: CGRect) -> some View {
        let intensity = sin(min(max(phase, 0), 1) * .pi)
        return LinearGradient(colors: [accent.opacity(intensity * 0.55), .clear], startPoint: .top, endPoint: .bottom)
            .frame(width: rect.width * 0.10, height: rect.height * 0.5)
            .position(x: rect.minX + rect.width * 0.5, y: rect.minY + rect.height * 0.12)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}
