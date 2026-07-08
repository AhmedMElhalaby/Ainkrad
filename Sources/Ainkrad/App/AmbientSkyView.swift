import SwiftUI

/// Accumulates virtual sky-time as the integral of the user's speed setting,
/// so changing speed ramps the motion smoothly instead of teleporting the
/// whole field (which `wallClock × speed` would do). Plain class on purpose:
/// mutating it per frame must never re-invalidate SwiftUI.
@MainActor
final class SkyClock {
    private var lastReal: Double?
    private var virtual: Double = 0

    func tick(real: Double, speed: Double) -> Double {
        virtual += max(0, real - (lastReal ?? real)) * speed
        lastReal = real
        return virtual
    }

    /// Back to the frozen arrangement's zero. Called when animation stops,
    /// so re-enabling resumes smoothly from exactly the pose the user was
    /// looking at instead of jump-cutting across the paused span.
    func reset() {
        lastReal = nil
        virtual = 0
    }
}

/// The OS "sky": an atmospheric, theme-driven backdrop behind every
/// workspace — deep vertical gradient, breathing horizon glow, aurora
/// ribbons, a drifting starfield, god-rays, horizon mist, fireflies, rising
/// embers, foreground bokeh, and rare sky events. Every effect is
/// individually switchable in Settings → Living Sky (`SkySettingsStore`),
/// with a master animate switch and speed control.
///
/// Deliberately game-like ambience rather than a flat app background; Reduce
/// Motion (or the master switch) freezes the whole field in its launch
/// arrangement.
struct AmbientSkyView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var clock = SkyClock()

    var body: some View {
        let tokens = environment.themeManager.tokens
        let sky = environment.skySettingsStore
        let animated = !reduceMotion && sky.motionEnabled

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

            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    layers(
                        at: clock.tick(
                            real: context.date.timeIntervalSinceReferenceDate,
                            speed: sky.motionSpeed
                        ),
                        sky: sky, tokens: tokens
                    )
                }
            } else {
                layers(at: 0, sky: sky, tokens: tokens)
            }
        }
        .ignoresSafeArea()
        .onChange(of: animated) { _, isAnimated in
            // The frozen branch shows the time-0 arrangement; rewind the
            // clock to match so re-enabling animates forward from that
            // exact pose rather than teleporting across the paused span.
            if !isAnimated { clock.reset() }
        }
    }

    /// Everything above the base gradient: the two glows (breathing when the
    /// effect is on), then the canvas of drawn effects. At `time == 0` (the
    /// frozen path) the glows sit exactly at their historical static values.
    @ViewBuilder
    private func layers(at time: TimeInterval, sky: SkySettingsStore, tokens: DesignTokens) -> some View {
        let breath = sky.isEnabled(.breathingSky) && time > 0 ? SkyMath.breath(time: time) : 0.5

        // Horizon glow — a sun below the edge of the island.
        RadialGradient(
            colors: [tokens.accentPrimary.opacity(0.16 + 0.12 * breath), .clear],
            center: .init(x: 0.5, y: 1.15),
            startRadius: 0,
            endRadius: 900
        )

        // High-altitude accent haze, offset so the two glows don't read as
        // symmetric.
        RadialGradient(
            colors: [tokens.accentSecondary.opacity(0.05 + 0.06 * breath), .clear],
            center: .init(x: 0.18, y: -0.1),
            startRadius: 0,
            endRadius: 700
        )

        canvas(at: time, sky: sky, tokens: tokens)
    }

    /// One Canvas pass, back to front. Each effect draws only while its
    /// switch is on; streaks and events need `time > 0` (they don't exist in
    /// the frozen arrangement).
    private func canvas(at time: TimeInterval, sky: SkySettingsStore, tokens: DesignTokens) -> some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            if sky.isEnabled(.aurora) {
                let surge = sky.isEnabled(.skyMoments) && time > 0 ? SkyMath.auroraSurge(time: time) : 0
                SkyRenderer.aurora(in: &context, size: size, time: time, surge: surge, tokens: tokens)
            }
            if sky.isEnabled(.lightRays) {
                SkyRenderer.lightRays(in: &context, size: size, time: time, tokens: tokens)
            }
            if sky.isEnabled(.stars) {
                SkyRenderer.stars(in: &context, size: size, time: time, tokens: tokens)
            }
            if time > 0, sky.isEnabled(.shootingStars), let streak = SkyMath.shootingStar(time: time) {
                SkyRenderer.streak(streak, in: &context, size: size, comet: false, tokens: tokens)
            }
            if time > 0, sky.isEnabled(.skyMoments) {
                for streak in SkyMath.meteorShower(time: time) {
                    SkyRenderer.streak(streak, in: &context, size: size, comet: false, tokens: tokens)
                }
                if let comet = SkyMath.comet(time: time) {
                    SkyRenderer.streak(comet, in: &context, size: size, comet: true, tokens: tokens)
                }
            }
            if sky.isEnabled(.horizonMist) {
                SkyRenderer.mist(in: &context, size: size, time: time, tokens: tokens)
            }
            if sky.isEnabled(.fireflies) {
                SkyRenderer.fireflies(in: &context, size: size, time: time, tokens: tokens)
            }
            if sky.isEnabled(.embers) {
                SkyRenderer.embers(in: &context, size: size, time: time, tokens: tokens)
            }
            if sky.isEnabled(.bokeh) {
                SkyRenderer.bokeh(in: &context, size: size, time: time, tokens: tokens)
            }
        }
        .allowsHitTesting(false)
    }
}
