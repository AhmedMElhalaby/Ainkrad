import CoreGraphics
import Foundation

/// Pure, deterministic motion for the Living Island layers. No wall-clock or
/// randomness — the same (seed, time) always yields the same offset, so it
/// previews/resumes without drift and is unit-testable. Mirrors the
/// discipline of `IslandState`.
enum IslandMotionMath {
    /// Horizontal-only drift for a cloud, bounded to ±18 pt. `seed` (0,1,2,…)
    /// varies each cloud's speed/phase/amplitude so the field isn't in
    /// lockstep. `time` is seconds.
    static func cloudDriftX(seed: Int, time: Double) -> CGFloat {
        let s = Double(seed)
        let speed = 0.18 + (s * 0.037).truncatingRemainder(dividingBy: 0.12)   // 0.18–0.30 rad/s
        let phase = (s * 1.7).truncatingRemainder(dividingBy: 2 * .pi)
        let amplitude = 10 + (s * 4.3).truncatingRemainder(dividingBy: 8)       // 10–18 pt
        return CGFloat(sin(time * speed + phase) * amplitude)
    }

    /// Vertical-only bob for an islet, bounded to ±8 pt. Varied per seed.
    static func isletBobY(seed: Int, time: Double) -> CGFloat {
        let s = Double(seed)
        let speed = 0.5 + (s * 0.071).truncatingRemainder(dividingBy: 0.4)      // 0.5–0.9 rad/s
        let phase = (s * 2.3).truncatingRemainder(dividingBy: 2 * .pi)
        let amplitude = 4 + (s * 2.7).truncatingRemainder(dividingBy: 4)        // 4–8 pt
        return CGFloat(sin(time * speed + phase) * amplitude)
    }
}
