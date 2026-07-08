import SwiftUI

/// Canvas drawing for every layer of the ambient sky. Pure functions of
/// (time, size, tokens) — all motion math lives in `SkyMath`, all gating in
/// `AmbientSkyView`. Kept apart from the view so each effect stays a small,
/// independently readable pass.
@MainActor
enum SkyRenderer {

    // MARK: Aurora

    /// Two vast, ultra-soft ribbons of accent light. Each segment is a
    /// screen-blended radial gradient squashed into a band; overlapping
    /// segments merge into one continuous, shimmering curtain. `surge`
    /// (0…1, from `SkyMath.auroraSurge`) blooms the whole curtain briefly.
    static func aurora(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval,
        surge: Double, tokens: DesignTokens
    ) {
        for ribbon in 0..<SkyMath.auroraRibbons {
            let color = ribbon == 0 ? tokens.accentPrimary : tokens.accentSecondary
            for segment in 0..<SkyMath.auroraSegments {
                let blob = SkyMath.auroraSegment(ribbon: ribbon, segment: segment, time: time)
                let radiusX = blob.radiusX * size.width
                let radiusY = blob.radiusY * size.width
                let opacity = blob.opacity * (1 + surge * 0.8)

                var layer = context
                layer.blendMode = .screen
                layer.translateBy(x: blob.x * size.width, y: blob.y * size.height)
                layer.scaleBy(x: 1, y: radiusY / radiusX)
                layer.fill(
                    Path(ellipseIn: CGRect(x: -radiusX, y: -radiusX,
                                           width: radiusX * 2, height: radiusX * 2)),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                        center: .zero, startRadius: 0, endRadius: radiusX
                    )
                )
            }
        }
    }

    // MARK: Stars

    /// The endlessly drifting starfield: twinkle always, glints only while
    /// animated (`time > 0`).
    static func stars(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval, tokens: DesignTokens
    ) {
        for index in 0..<SkyMath.starCount {
            let star = SkyMath.star(index: index)
            let position = SkyMath.position(index: index, time: time)
            let x = position.x * size.width
            let y = position.y * size.height

            let glint = time > 0 ? SkyMath.glint(index: index, time: time) : 0
            let brightness = min(
                star.baseOpacity * SkyMath.twinkle(index: index, time: time) + glint * 0.45,
                0.9
            )

            let radius = star.radius * (1 + glint * 0.8)
            let color = (star.isAccent ? tokens.accentSecondary : tokens.foreground)
                .opacity(brightness)
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            if glint > 0 {
                // Soft halo while a star glints.
                context.fill(
                    Path(ellipseIn: rect.insetBy(dx: -radius * 1.6, dy: -radius * 1.6)),
                    with: .color(color.opacity(0.25))
                )
            }
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    // MARK: Streaks (shooting stars, meteor showers, the comet)

    /// One streak. `comet: true` draws the slow crossing — longer tail,
    /// wider glow, and a bright head.
    static func streak(
        _ streak: SkyMath.ShootingStar,
        in context: inout GraphicsContext, size: CGSize, comet: Bool, tokens: DesignTokens
    ) {
        let inclination = abs(streak.angle)
        let direction = CGVector(
            dx: (streak.angle >= 0 ? 1 : -1) * cos(inclination),
            dy: sin(inclination)                     // always descending
        )
        let travel = size.width * (comet ? 0.55 : 0.22)
        let length = size.width * (comet ? 0.16 : 0.10)
        let head = CGPoint(
            x: streak.startX * size.width + direction.dx * travel * streak.progress,
            y: streak.startY * size.height + direction.dy * travel * streak.progress
        )
        let tail = CGPoint(x: head.x - direction.dx * length, y: head.y - direction.dy * length)

        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)

        // Wide soft glow beneath a bright core that fades along its tail.
        context.stroke(
            path,
            with: .color(tokens.accentPrimary.opacity((comet ? 0.35 : 0.25) * streak.brightness)),
            lineWidth: comet ? 6 : 3.5
        )
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    tokens.accentPrimary.opacity(0),
                    tokens.foreground.opacity(0.85 * streak.brightness),
                ]),
                startPoint: tail,
                endPoint: head
            ),
            lineWidth: comet ? 1.8 : 1.4
        )
        if comet {
            let headRadius = 2.6
            context.fill(
                Path(ellipseIn: CGRect(x: head.x - headRadius, y: head.y - headRadius,
                                       width: headRadius * 2, height: headRadius * 2)),
                with: .color(tokens.foreground.opacity(0.9 * streak.brightness))
            )
        }
    }

    // MARK: Atmosphere

    /// Faint fog bands sliding sideways near the horizon.
    static func mist(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval, tokens: DesignTokens
    ) {
        for index in 0..<SkyMath.mistBands {
            let band = SkyMath.mistBand(index: index, time: time)
            let radiusX = band.radiusX * size.width
            let radiusY = band.radiusY * size.width

            var layer = context
            layer.blendMode = .screen
            layer.translateBy(x: band.x * size.width, y: band.y * size.height)
            layer.scaleBy(x: 1, y: radiusY / radiusX)
            layer.fill(
                Path(ellipseIn: CGRect(x: -radiusX, y: -radiusX,
                                       width: radiusX * 2, height: radiusX * 2)),
                with: .radialGradient(
                    Gradient(colors: [tokens.foreground.opacity(band.opacity), tokens.foreground.opacity(0)]),
                    center: .zero, startRadius: 0, endRadius: radiusX
                )
            )
        }
    }

    /// Soft god-rays fanning up from the below-horizon sun (the same point
    /// the horizon glow radiates from), swaying almost imperceptibly.
    static func lightRays(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval, tokens: DesignTokens
    ) {
        let sun = CGPoint(x: size.width * 0.5, y: size.height * 1.15)
        for index in 0..<SkyMath.lightRayCount {
            let ray = SkyMath.lightRay(index: index, time: time)
            let width = ray.width * size.width
            let reach = size.height * 1.05

            var layer = context
            layer.blendMode = .screen
            layer.translateBy(x: sun.x, y: sun.y)
            layer.rotate(by: .radians(ray.angle))
            layer.fill(
                Path(CGRect(x: -width / 2, y: -reach, width: width, height: reach)),
                with: .linearGradient(
                    Gradient(colors: [tokens.accentPrimary.opacity(ray.opacity), tokens.accentPrimary.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: -reach)
                )
            )
        }
    }

    // MARK: Fireflies and bokeh

    /// Accent energy motes rising through the island's region, each with a
    /// soft halo.
    static func fireflies(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval, tokens: DesignTokens
    ) {
        for index in 0..<SkyMath.fireflyCount {
            let fly = SkyMath.firefly(index: index, time: time)
            guard fly.opacity > 0.005 else { continue }
            let x = fly.x * size.width
            let y = fly.y * size.height
            let color = tokens.accentSecondary

            let halo = fly.radius * 2.4
            context.fill(
                Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2)),
                with: .color(color.opacity(fly.opacity * 0.3))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: x - fly.radius, y: y - fly.radius,
                                       width: fly.radius * 2, height: fly.radius * 2)),
                with: .color(color.opacity(fly.opacity))
            )
        }
    }

    /// Large, ultra-faint out-of-focus orbs in the extreme foreground —
    /// drawn last, over everything in the sky.
    static func bokeh(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval, tokens: DesignTokens
    ) {
        for index in 0..<SkyMath.bokehCount {
            let orb = SkyMath.bokehOrb(index: index, time: time)
            let radius = orb.radius * size.width
            let color = index.isMultiple(of: 2) ? tokens.foreground : tokens.accentPrimary

            var layer = context
            layer.blendMode = .screen
            layer.fill(
                Path(ellipseIn: CGRect(x: orb.x * size.width - radius, y: orb.y * size.height - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(orb.opacity), color.opacity(0)]),
                    center: CGPoint(x: orb.x * size.width, y: orb.y * size.height),
                    startRadius: 0, endRadius: radius
                )
            )
        }
    }

    // MARK: Embers

    /// ~70 embers, deterministically placed from their index, drifting
    /// upward and twinkling.
    static func embers(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval, tokens: DesignTokens
    ) {
        for index in 0..<SkyMath.emberCount {
            let ember = SkyMath.ember(index: index, time: time)
            let x = ember.x * size.width
            let y = ember.y * size.height
            let color = (ember.isAccent ? tokens.accentSecondary : tokens.foreground)
                .opacity(ember.opacity)
            let rect = CGRect(x: x - ember.radius, y: y - ember.radius,
                              width: ember.radius * 2, height: ember.radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}
