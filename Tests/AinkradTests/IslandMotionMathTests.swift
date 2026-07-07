import Testing
import CoreGraphics
@testable import Ainkrad

@Suite("IslandMotionMath")
struct IslandMotionMathTests {
    @Test("cloud drift is bounded to ±18 across seeds and time")
    func cloudDriftBounded() {
        for seed in 0..<8 {
            for step in 0..<400 {
                let t = Double(step) * 0.13
                let x = IslandMotionMath.cloudDriftX(seed: seed, time: t)
                #expect(abs(x) <= 52.0)
            }
        }
    }

    @Test("islet bob is bounded to ±8 across seeds and time")
    func isletBobBounded() {
        for seed in 0..<9 {
            for step in 0..<400 {
                let t = Double(step) * 0.13
                let y = IslandMotionMath.isletBobY(seed: seed, time: t)
                #expect(abs(y) <= 18.0)
            }
        }
    }

    @Test("motion is deterministic for identical inputs")
    func deterministic() {
        #expect(IslandMotionMath.cloudDriftX(seed: 3, time: 12.5) == IslandMotionMath.cloudDriftX(seed: 3, time: 12.5))
        #expect(IslandMotionMath.isletBobY(seed: 5, time: 7.25) == IslandMotionMath.isletBobY(seed: 5, time: 7.25))
    }

    @Test("distinct seeds diverge")
    func seedsDiverge() {
        // Over a sweep, seed 0 and seed 1 must differ somewhere (not lockstep).
        var differ = false
        for step in 0..<200 {
            let t = Double(step) * 0.1
            if IslandMotionMath.cloudDriftX(seed: 0, time: t) != IslandMotionMath.cloudDriftX(seed: 1, time: t) { differ = true; break }
        }
        #expect(differ)
    }

    @Test("cloud drift is non-trivial (actually moves)")
    func cloudMoves() {
        let a = IslandMotionMath.cloudDriftX(seed: 2, time: 0)
        var moved = false
        for step in 1..<200 where abs(IslandMotionMath.cloudDriftX(seed: 2, time: Double(step) * 0.1) - a) > 1 { moved = true; break }
        #expect(moved)
    }
}
