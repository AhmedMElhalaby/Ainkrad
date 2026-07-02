import SwiftUI
import AppKit

/// Two non-overlapping panes separated by an "energy seam": a thin accent
/// gradient line in the gap between floating Blocks that brightens on
/// hover and while dragging. When `resizeAnchorID` is nil the split has no
/// leaf child `TileLayout.setRatio` can address, so the seam is static.
struct SplitView<First: View, Second: View>: View {
    @Environment(AppEnvironment.self) private var environment
    let axis: SplitAxis
    let ratio: Double
    /// True while a magnified Block collapses this split — the gap and
    /// seam disappear so the magnified side fills the canvas.
    var isCollapsed = false
    let resizeAnchorID: UUID?
    let tileLayout: TileLayout
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    @State private var isHovering = false
    @State private var isDragging = false

    /// The visible gap between Blocks; the seam line draws centered in it
    /// and the drag hit area spans the whole gap plus a little more.
    private var gap: CGFloat { isCollapsed ? 0 : 8 }

    var body: some View {
        GeometryReader { proxy in
            let totalLength = axis == .vertical ? proxy.size.width : proxy.size.height
            let firstLength = max(0, totalLength * ratio - gap / 2)

            let stack = axis == .vertical
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))

            stack {
                first()
                    .frame(
                        width: axis == .vertical ? firstLength : nil,
                        height: axis == .horizontal ? firstLength : nil
                    )
                seam(totalLength: totalLength)
                second()
            }
        }
    }

    @ViewBuilder
    private func seam(totalLength: CGFloat) -> some View {
        let tokens = environment.themeManager.tokens
        let isLit = (isHovering || isDragging) && !isCollapsed
        let line = Group {
            if axis == .vertical {
                LinearGradient(
                    colors: [.clear, tokens.accentSecondary.opacity(isLit ? 0.9 : 0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: isLit ? 2 : 1)
            } else {
                LinearGradient(
                    colors: [.clear, tokens.accentSecondary.opacity(isLit ? 0.9 : 0.22), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: isLit ? 2 : 1)
            }
        }
        .shadow(color: isLit ? tokens.accentSecondary.opacity(0.7) : .clear, radius: 5)
        .frame(
            width: axis == .vertical ? gap : nil,
            height: axis == .horizontal ? gap : nil
        )
        .animation(.easeOut(duration: 0.12), value: isLit)

        if let resizeAnchorID, !isCollapsed {
            line
                .contentShape(Rectangle().inset(by: -2))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let offset = axis == .vertical ? value.location.x : value.location.y
                            let newRatio = min(max(offset / totalLength, 0.1), 0.9)
                            tileLayout.setRatio(newRatio, for: resizeAnchorID)
                        }
                        .onEnded { _ in isDragging = false }
                )
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        } else {
            line
        }
    }
}
