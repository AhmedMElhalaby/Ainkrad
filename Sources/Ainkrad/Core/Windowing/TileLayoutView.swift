import SwiftUI
import AppKit

/// Renders one workspace's balanced pane grid, or the empty-state hint
/// when it has no open panes. See Window & Tile Management Architecture.md.
struct TileLayoutView: View {
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    var body: some View {
        if tileLayout.isEmpty {
            EmptyWorkspaceView()
        } else {
            // Breathing room around the floating panes — the sky stays
            // visible at the canvas edges.
            GridLayoutView(tileLayout: tileLayout, registry: registry)
                .padding([.horizontal, .bottom], 10)
                .padding(.top, 4)
                .animation(.easeInOut(duration: 0.2), value: tileLayout.magnifiedBlockID)
                .animation(.easeOut(duration: 0.18), value: tileLayout.appIDs)
        }
    }
}

/// The Termius-style balanced grid: rows of equal-by-default panes with
/// energy-seam boundaries between rows and columns. While a pane is
/// magnified, everything else collapses to zero (but stays mounted, so
/// sessions keep running) and the magnified pane fills the canvas.
struct GridLayoutView: View {
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    var body: some View {
        GeometryReader { proxy in
            let grid = tileLayout.grid
            let magnifiedID = tileLayout.magnifiedBlockID
            let gap: CGFloat = magnifiedID == nil ? 8 : 0
            let rowFractions = effectiveRowFractions(grid: grid, magnifiedID: magnifiedID)
            let rowSeams = CGFloat(max(grid.count - 1, 0)) * gap
            let availableHeight = max(proxy.size.height - rowSeams, 0)

            VStack(spacing: 0) {
                ForEach(Array(grid.enumerated()), id: \.offset) { rowIndex, row in
                    gridRow(
                        row,
                        rowIndex: rowIndex,
                        magnifiedID: magnifiedID,
                        gap: gap,
                        width: proxy.size.width
                    )
                    .frame(height: availableHeight * rowFractions[rowIndex])

                    if rowIndex < grid.count - 1 {
                        SeamView(axis: .horizontal, gap: gap, isDisabled: magnifiedID != nil) { location in
                            tileLayout.setRowBoundary(after: rowIndex, to: location.y / max(proxy.size.height, 1))
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: "tile-grid")
    }

    private func gridRow(_ row: [Block], rowIndex: Int, magnifiedID: UUID?, gap: CGFloat, width: CGFloat) -> some View {
        let columnFractions = effectiveColumnFractions(row: row, rowIndex: rowIndex, magnifiedID: magnifiedID)
        let columnSeams = CGFloat(max(row.count - 1, 0)) * gap
        let availableWidth = max(width - columnSeams, 0)

        return HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.element.id) { columnIndex, block in
                BlockView(block: block, tileLayout: tileLayout, registry: registry)
                    .frame(width: availableWidth * columnFractions[columnIndex])

                if columnIndex < row.count - 1 {
                    SeamView(axis: .vertical, gap: gap, isDisabled: magnifiedID != nil) { location in
                        tileLayout.setColumnBoundary(inRow: rowIndex, after: columnIndex, to: location.x / max(width, 1))
                    }
                }
            }
        }
    }

    /// Stored fractions, overridden while magnified: the magnified pane's
    /// row/column takes 1.0 and everything else 0. Falls back to equal
    /// shares if stored fractions are momentarily out of sync.
    private func effectiveRowFractions(grid: [[Block]], magnifiedID: UUID?) -> [Double] {
        if let magnifiedID {
            return grid.map { row in row.contains(where: { $0.id == magnifiedID }) ? 1.0 : 0.0 }
        }
        let stored = tileLayout.rowFractions
        guard stored.count == grid.count else {
            return Array(repeating: 1.0 / Double(max(grid.count, 1)), count: grid.count)
        }
        return stored
    }

    private func effectiveColumnFractions(row: [Block], rowIndex: Int, magnifiedID: UUID?) -> [Double] {
        if let magnifiedID {
            return row.map { $0.id == magnifiedID ? 1.0 : 0.0 }
        }
        let stored = tileLayout.columnFractions
        guard stored.indices.contains(rowIndex), stored[rowIndex].count == row.count else {
            return Array(repeating: 1.0 / Double(max(row.count, 1)), count: row.count)
        }
        return stored[rowIndex]
    }
}

/// An energy seam between panes: a thin accent gradient line centered in
/// the gap that brightens on hover and while dragging to resize.
private struct SeamView: View {
    enum Axis { case horizontal, vertical }

    @Environment(AppEnvironment.self) private var environment
    let axis: Axis
    let gap: CGFloat
    let isDisabled: Bool
    let onResize: (CGPoint) -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        let tokens = environment.themeManager.tokens
        let isLit = (isHovering || isDragging) && !isDisabled

        Group {
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
        .contentShape(Rectangle().inset(by: -2))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("tile-grid"))
                .onChanged { value in
                    guard !isDisabled else { return }
                    isDragging = true
                    onResize(value.location)
                }
                .onEnded { _ in isDragging = false }
        )
        .onHover { hovering in
            isHovering = hovering
            guard !isDisabled else { return }
            if hovering {
                (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.12), value: isLit)
    }
}
