import CoreGraphics

/// Pure math that composes the 2.5D parallax offset for the Living Island
/// home artwork from three independent inputs: pointer position, a slow
/// idle drift, and a workspace-switch "banking" impulse.
///
/// Convention: the near plane follows the pointer. A pointer to the RIGHT
/// (`pointerFraction.x == 1`) moves the near plane toward `+x`
/// (`offset.width > 0`).
enum IslandParallaxMath {
    /// Weight applied to the pointer term before combining — the dominant input.
    private static let pointerWeight: CGFloat = 1.0
    /// Weight applied to the idle drift term before combining.
    private static let idleWeight: CGFloat = 0.3

    /// Clamp a raw location fraction into -1...1 on each axis.
    static func clampFraction(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, -1), 1), y: min(max(p.y, -1), 1))
    }

    /// Compose the parallax vector (in points) from pointer, idle drift, and banking.
    /// - pointerFraction: -1...1 each axis (.zero when not hovering) — dominant term.
    /// - idle: a normalized -1...1 slow-drift vector (Lissajous); contributes ~30%.
    /// - banking: signed -1...1 horizontal workspace-switch impulse; adds to width.
    /// - maxOffset: max magnitude per axis, in points.
    /// Returns a CGSize whose width/height magnitude never exceeds maxOffset.
    static func offset(pointerFraction: CGPoint, idle: CGPoint, banking: Double, maxOffset: CGFloat) -> CGSize {
        let pointer = clampFraction(pointerFraction)
        let idleClamped = clampFraction(idle)
        let bankingClamped = min(max(banking, -1), 1)

        let combinedX = pointer.x * pointerWeight + idleClamped.x * idleWeight + CGFloat(bankingClamped)
        let combinedY = pointer.y * pointerWeight + idleClamped.y * idleWeight

        let width = min(max(combinedX * maxOffset, -maxOffset), maxOffset)
        let height = min(max(combinedY * maxOffset, -maxOffset), maxOffset)

        return CGSize(width: width, height: height)
    }
}
