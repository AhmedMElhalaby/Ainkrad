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
            .onReceive(tickTimer) { _ in
                guard isVisible && !reduceMotion else { return }
                environment.islandState.tick(dt: 1.0 / 60.0)
            }
            .onChange(of: environment.isLauncherPresented) { _, open in
                environment.islandState.launcherActive(open)
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
                layerView(layer, rect: rect, time: time)
            }
            if animating, let phase = environment.islandState.flarePhase {
                flare(phase: phase, rect: rect)
            }
            hoverTargets(rect: rect)
        }
        .offset(x: bank)
    }

    @ViewBuilder
    private func hoverTargets(rect: CGRect) -> some View {
        // Ring: annulus band only.
        if let ring = IslandLayers.all.first(where: { $0.kind == .ring }) {
            let w = rect.width * ring.width
            let h = rect.height * 0.5615    // ring height fraction (from extraction); matches drawn ring
            IslandRingBand()
                .fill(Color.white.opacity(0.001), style: FillStyle(eoFill: true))
                .frame(width: w, height: h)
                .position(x: rect.minX + rect.width * ring.cx, y: rect.minY + rect.height * ring.cy)
                .onHover { setHover(.ring, $0) }
        }
        // Chevron / logo / slogan: rectangular targets at their own bounds.
        ForEach(IslandLayers.all.filter { [.chevron, .logo, .slogan].contains($0.kind) }) { layer in
            let w = rect.width * layer.width
            let h = rect.height * hoverHeight(for: layer.kind)
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: w, height: h)
                .position(x: rect.minX + rect.width * layer.cx, y: rect.minY + rect.height * layer.cy)
                .onHover { setHover(layer.kind, $0) }
        }
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

    private func setHover(_ kind: IslandLayer.Kind, _ inside: Bool) {
        withAnimation(.easeOut(duration: 0.22)) {
            if inside { hovered = kind }
            else if hovered == kind { hovered = nil }
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
    private func layerView(_ layer: IslandLayer, rect: CGRect, time: Double) -> some View {
        let w = rect.width * layer.width
        let px = rect.minX + rect.width * layer.cx
        let py = rect.minY + rect.height * layer.cy
        let dx: CGFloat = layer.kind == .cloud ? IslandMotionMath.cloudDriftX(seed: layer.seed ?? 0, time: time) : 0
        let dy: CGFloat = layer.kind == .islet ? IslandMotionMath.isletBobY(seed: layer.seed ?? 0, time: time) : 0
        Image(layer.id)
            .resizable()
            .scaledToFit()
            .frame(width: w)
            .colorMultiply(tint(for: layer))
            .brightness(layer.kind == .ring ? environment.islandState.ringIntensity * 0.12 : 0)
            .shadow(color: ringGlowColor(layer), radius: layer.kind == .ring ? 10 + environment.islandState.ringIntensity * 14 : 0)
            .brightness(hovered == layer.kind ? 0.14 : 0)
            .shadow(color: hovered == layer.kind ? accent.opacity(0.9) : .clear, radius: hovered == layer.kind ? 16 : 0)
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
