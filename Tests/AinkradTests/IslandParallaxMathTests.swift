import Testing
import CoreGraphics
@testable import Ainkrad

@Suite("IslandParallaxMath")
struct IslandParallaxMathTests {
    @Test("clampFraction clamps out-of-range components to ±1 and leaves in-range untouched")
    func clampFractionClamps() {
        let clamped = IslandParallaxMath.clampFraction(CGPoint(x: 2.5, y: -3.2))
        #expect(clamped.x == 1)
        #expect(clamped.y == -1)

        let untouched = IslandParallaxMath.clampFraction(CGPoint(x: 0.4, y: -0.6))
        #expect(abs(untouched.x - 0.4) < 0.001)
        #expect(abs(untouched.y - (-0.6)) < 0.001)
    }

    @Test("zero pointer, idle, and banking produce a zero offset")
    func zeroInputsProduceZeroOffset() {
        let offset = IslandParallaxMath.offset(
            pointerFraction: .zero,
            idle: .zero,
            banking: 0,
            maxOffset: 18
        )
        #expect(offset == .zero)
    }

    @Test("full-right pointer moves the near plane toward +x, clamped to maxOffset")
    func fullRightPointerMovesTowardPositiveX() {
        let offset = IslandParallaxMath.offset(
            pointerFraction: CGPoint(x: 1, y: 0),
            idle: .zero,
            banking: 0,
            maxOffset: 18
        )
        #expect(offset.width > 0)
        #expect(abs(offset.width) <= 18)
        #expect(abs(offset.height) < 0.001)
    }

    @Test("positive banking with zero pointer/idle shifts width in banking's sign")
    func bankingShiftsWidthInItsSign() {
        let positive = IslandParallaxMath.offset(
            pointerFraction: .zero,
            idle: .zero,
            banking: 1,
            maxOffset: 18
        )
        #expect(positive.width > 0)

        let negative = IslandParallaxMath.offset(
            pointerFraction: .zero,
            idle: .zero,
            banking: -1,
            maxOffset: 18
        )
        #expect(negative.width < 0)
    }

    @Test("combined extreme inputs never exceed maxOffset on either axis")
    func combinedExtremesStayWithinMaxOffset() {
        let maxOffset: CGFloat = 18
        let signs: [CGFloat] = [-1, 1]
        for sx in signs {
            for sy in signs {
                for sb in signs {
                    let offset = IslandParallaxMath.offset(
                        pointerFraction: CGPoint(x: sx, y: sy),
                        idle: CGPoint(x: sx, y: sy),
                        banking: Double(sb),
                        maxOffset: maxOffset
                    )
                    #expect(abs(offset.width) <= maxOffset)
                    #expect(abs(offset.height) <= maxOffset)
                }
            }
        }
    }

    @Test("idle-only input produces smaller magnitude than pointer-only for the same normalized value")
    func idleIsWeightedDownRelativeToPointer() {
        let maxOffset: CGFloat = 18
        let pointerOnly = IslandParallaxMath.offset(
            pointerFraction: CGPoint(x: 1, y: 1),
            idle: .zero,
            banking: 0,
            maxOffset: maxOffset
        )
        let idleOnly = IslandParallaxMath.offset(
            pointerFraction: .zero,
            idle: CGPoint(x: 1, y: 1),
            banking: 0,
            maxOffset: maxOffset
        )
        #expect(abs(idleOnly.width) < abs(pointerOnly.width))
        #expect(abs(idleOnly.height) < abs(pointerOnly.height))
    }
}
