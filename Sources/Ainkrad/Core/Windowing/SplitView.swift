import SwiftUI
import AppKit

/// Two non-overlapping panes divided by a thin, draggable divider. When
/// `resizeAnchorID` is nil the split has no leaf child `TileLayout.setRatio`
/// can address, so the divider is static.
struct SplitView<First: View, Second: View>: View {
    let axis: SplitAxis
    let ratio: Double
    let resizeAnchorID: UUID?
    let tileLayout: TileLayout
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    private let dividerThickness: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let totalLength = axis == .vertical ? proxy.size.width : proxy.size.height
            let firstLength = max(0, totalLength * ratio - dividerThickness / 2)

            let stack = axis == .vertical
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))

            stack {
                first()
                    .frame(
                        width: axis == .vertical ? firstLength : nil,
                        height: axis == .horizontal ? firstLength : nil
                    )
                divider(totalLength: totalLength)
                second()
            }
        }
    }

    @ViewBuilder
    private func divider(totalLength: CGFloat) -> some View {
        let shape = Rectangle()
            .fill(.white.opacity(0.08))
            .frame(
                width: axis == .vertical ? dividerThickness : nil,
                height: axis == .horizontal ? dividerThickness : nil
            )

        if let resizeAnchorID {
            shape
                .contentShape(Rectangle().inset(by: -3))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let offset = axis == .vertical ? value.location.x : value.location.y
                            let newRatio = min(max(offset / totalLength, 0.1), 0.9)
                            tileLayout.setRatio(newRatio, for: resizeAnchorID)
                        }
                )
                .onHover { isHovering in
                    if isHovering {
                        (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        } else {
            shape
        }
    }
}
