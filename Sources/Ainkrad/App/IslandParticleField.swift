import SwiftUI

/// Slow drifting light motes rendered over the Living Island artwork — an
/// ambient "alive" layer echoing the artwork's stippled particle edge.
/// Deterministically seeded from each mote's index (no wall-clock/random at
/// init) so it's preview- and resume-stable; only `TimelineView`'s date
/// drives motion.
struct IslandParticleField: View {
    var tint: Color
    /// A fraction of the island's parallax offset, so motes sit "in" the scene.
    var parallax: CGSize
    /// When false, renders nothing (Reduce Motion / not visible) — no TimelineView runs.
    var isActive: Bool

    private static let moteCount = 48
    /// Fraction of the scene's parallax offset applied to each mote.
    private static let parallaxFraction: CGFloat = 0.4
    /// Margin (points) beyond the top/bottom edge before a mote wraps.
    private static let wrapMargin: CGFloat = 24

    var body: some View {
        if isActive {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                motes(at: context.date.timeIntervalSinceReferenceDate)
            }
            .allowsHitTesting(false)
        } else {
            Color.clear
                .allowsHitTesting(false)
        }
    }

    private func motes(at time: TimeInterval) -> some View {
        let offset = CGSize(
            width: parallax.width * Self.parallaxFraction,
            height: parallax.height * Self.parallaxFraction
        )

        return Canvas { context, size in
            context.addFilter(.blur(radius: 0.6))

            for index in 0..<Self.moteCount {
                let spec = Self.spec(at: index)

                let baseX = spec.xFraction * size.width + offset.width
                let wanderX = sin(time * spec.wanderSpeed + spec.wanderPhase) * spec.wanderAmplitude
                let x = baseX + wanderX

                let baseY = spec.yFraction * size.height
                let travel = (baseY - time * spec.driftSpeed)
                    .truncatingRemainder(dividingBy: size.height + Self.wrapMargin)
                let wrappedY = travel < -Self.wrapMargin ? travel + size.height + Self.wrapMargin : travel
                let y = wrappedY + offset.height

                let twinkle = 0.5 + 0.5 * sin(time * spec.twinkleSpeed + spec.twinklePhase)
                let opacity = spec.baseOpacity * twinkle

                let rect = CGRect(
                    x: x - spec.radius,
                    y: y - spec.radius,
                    width: spec.radius * 2,
                    height: spec.radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(opacity)))
            }
        }
    }

    /// Per-mote motion parameters, derived purely from `index` via a cheap
    /// deterministic hash (no `Double.random`, no wall-clock reads).
    private struct MoteSpec {
        var xFraction: CGFloat
        var yFraction: CGFloat
        var radius: CGFloat
        var driftSpeed: Double
        var wanderAmplitude: CGFloat
        var wanderSpeed: Double
        var wanderPhase: Double
        var twinkleSpeed: Double
        var twinklePhase: Double
        var baseOpacity: Double
    }

    /// Pseudo-random 0..<1 stream for `index`, decorrelated per `salt`.
    private static func hash(_ index: Int, salt: Double) -> Double {
        let seed = Double(index) + 1
        return abs((sin(seed * salt) * 43_758.5453).truncatingRemainder(dividingBy: 1))
    }

    private static func spec(at index: Int) -> MoteSpec {
        let r1 = hash(index, salt: 12.9898)
        let r2 = hash(index, salt: 78.233)
        let r3 = hash(index, salt: 39.346)
        let r4 = hash(index, salt: 4.1414)
        let r5 = hash(index, salt: 93.989)
        let r6 = hash(index, salt: 27.619)
        let r7 = hash(index, salt: 61.129)
        let r8 = hash(index, salt: 8.815)

        // Averaging two independent uniforms yields a triangular
        // distribution peaked at 0.5 — motes cluster toward the horizontal
        // center, echoing the citadel silhouette.
        let xFraction = (r1 + r2) / 2

        return MoteSpec(
            xFraction: xFraction,
            yFraction: r3,
            radius: 0.8 + r4 * 1.8,
            driftSpeed: 3 + r5 * 6,
            wanderAmplitude: 4 + r6 * 10,
            wanderSpeed: 0.15 + r7 * 0.3,
            wanderPhase: r1 * 2 * .pi,
            twinkleSpeed: 0.4 + r8 * 0.8,
            twinklePhase: r2 * 2 * .pi,
            baseOpacity: 0.18 + r7 * 0.3
        )
    }
}
