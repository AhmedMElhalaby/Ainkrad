import SwiftUI

/// The OS "sky": an atmospheric, theme-driven backdrop behind every
/// workspace — deep vertical gradient, a soft horizon glow, and slowly
/// rising ember particles. Deliberately game-like ambience rather than a
/// flat app background; honors Reduce Motion by freezing the particles.
struct AmbientSkyView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tokens = environment.themeManager.tokens

        ZStack {
            LinearGradient(
                stops: [
                    .init(color: tokens.background, location: 0),
                    .init(color: tokens.surface, location: 0.55),
                    .init(color: tokens.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Horizon glow — a sun below the edge of the island.
            RadialGradient(
                colors: [tokens.accentPrimary.opacity(0.22), .clear],
                center: .init(x: 0.5, y: 1.15),
                startRadius: 0,
                endRadius: 900
            )

            // High-altitude accent haze, offset so the two glows don't
            // read as symmetric.
            RadialGradient(
                colors: [tokens.accentSecondary.opacity(0.08), .clear],
                center: .init(x: 0.18, y: -0.1),
                startRadius: 0,
                endRadius: 700
            )

            if reduceMotion {
                particles(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                    particles(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// ~70 embers, deterministically placed from their index, drifting
    /// upward and twinkling. Pure Canvas drawing — no view churn.
    private func particles(at time: TimeInterval) -> some View {
        let tokens = environment.themeManager.tokens

        return Canvas { canvasContext, size in
            for index in 0..<70 {
                let seed = Double(index)
                let x = (seed * 127.153).truncatingRemainder(dividingBy: 1) * size.width
                let speed = 4 + (seed * 31.7).truncatingRemainder(dividingBy: 1) * 9
                let baseY = (seed * 311.7).truncatingRemainder(dividingBy: 1) * size.height
                let y = (baseY - time * speed).truncatingRemainder(dividingBy: size.height + 20)
                let wrappedY = y < -10 ? y + size.height + 20 : y

                let twinkle = 0.5 + 0.5 * sin(time * (0.6 + (seed * 17.3).truncatingRemainder(dividingBy: 1)) + seed)
                let radius = 0.6 + (seed * 53.9).truncatingRemainder(dividingBy: 1) * 1.3
                let isAccent = index % 9 == 0

                let color = (isAccent ? tokens.accentSecondary : tokens.foreground)
                    .opacity((isAccent ? 0.5 : 0.22) * twinkle)
                let rect = CGRect(x: x, y: wrappedY, width: radius * 2, height: radius * 2)
                canvasContext.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}
