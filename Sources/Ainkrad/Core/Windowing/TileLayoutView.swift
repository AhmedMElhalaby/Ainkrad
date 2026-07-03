import SwiftUI
import AppKit

/// Renders one workspace's pane tree, or the empty-state hint when it has
/// no open panes. See Window & Tile Management Architecture.md.
struct TileLayoutView: View {
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    var body: some View {
        if tileLayout.isEmpty {
            EmptyWorkspaceView()
        } else if let root = tileLayout.root {
            // Breathing room around the floating panes — the sky stays
            // visible at the canvas edges.
            PaneTreeView(node: root, path: [], tileLayout: tileLayout, registry: registry)
                .padding([.horizontal, .bottom], 10)
                .padding(.top, 4)
                .animation(.easeInOut(duration: 0.2), value: tileLayout.magnifiedBlockID)
                .animation(.easeOut(duration: 0.18), value: tileLayout.appIDs)
        }
    }
}

/// Recursively renders one node of the N-ary split tree: a pane for a
/// leaf, or children laid along the container's axis with energy seams
/// between them. While a pane is magnified, every container on its path
/// gives it 100% and collapses the rest to zero (still mounted, so
/// sessions keep running).
struct PaneTreeView: View {
    let node: PaneNode
    let path: [Int]
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    var body: some View {
        switch node {
        case .leaf(let block):
            BlockView(block: block, tileLayout: tileLayout, registry: registry)
        case .split(let axis, let children, let fractions):
            container(axis: axis, children: children, fractions: fractions)
        }
    }

    private func container(axis: PaneAxis, children: [PaneNode], fractions: [Double]) -> some View {
        GeometryReader { proxy in
            let isMagnifyActive = tileLayout.magnifiedBlockID != nil
            let gap: CGFloat = isMagnifyActive ? 0 : 8
            let effective = effectiveFractions(children: children, fractions: fractions, isMagnifyActive: isMagnifyActive)
            let total = axis == .horizontal ? proxy.size.width : proxy.size.height
            let available = max(total - CGFloat(children.count - 1) * gap, 0)
            let spaceName = "pane-container-\(path.map(String.init).joined(separator: "."))"

            let stack = axis == .horizontal
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))

            stack {
                ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                    PaneTreeView(node: child, path: path + [index], tileLayout: tileLayout, registry: registry)
                        .frame(
                            width: axis == .horizontal ? available * effective[index] : nil,
                            height: axis == .vertical ? available * effective[index] : nil
                        )

                    if index < children.count - 1 {
                        SeamView(
                            axis: axis,
                            gap: gap,
                            isDisabled: isMagnifyActive,
                            coordinateSpace: spaceName
                        ) { location in
                            let position = axis == .horizontal
                                ? location.x / max(proxy.size.width, 1)
                                : location.y / max(proxy.size.height, 1)
                            tileLayout.setBoundary(path: path, after: index, to: position)
                        }
                    }
                }
            }
            .coordinateSpace(name: spaceName)
        }
    }

    /// Stored fractions, overridden while a pane is magnified: the child
    /// whose subtree holds it takes 1.0, everything else 0.
    private func effectiveFractions(children: [PaneNode], fractions: [Double], isMagnifyActive: Bool) -> [Double] {
        if isMagnifyActive {
            return children.map { tileLayout.subtreeContainsMagnifiedBlock($0) ? 1.0 : 0.0 }
        }
        guard fractions.count == children.count else {
            return Array(repeating: 1.0 / Double(max(children.count, 1)), count: children.count)
        }
        return fractions
    }
}

/// An energy seam between sibling panes: a thin accent gradient line in
/// the gap, with a grabber capsule that brightens on hover and while
/// dragging to resize.
private struct SeamView: View {
    @Environment(AppEnvironment.self) private var environment
    let axis: PaneAxis
    let gap: CGFloat
    let isDisabled: Bool
    let coordinateSpace: String
    let onResize: (CGPoint) -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        let tokens = environment.themeManager.tokens
        let isLit = (isHovering || isDragging) && !isDisabled

        Group {
            if axis == .horizontal {
                // Children side by side → vertical seam line.
                LinearGradient(
                    colors: [.clear, tokens.accentSecondary.opacity(isLit ? 0.9 : 0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: isLit ? 2 : 1)
                .overlay {
                    if isLit {
                        Capsule()
                            .fill(tokens.accentSecondary)
                            .frame(width: 3, height: 22)
                            .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 4)
                    }
                }
            } else {
                LinearGradient(
                    colors: [.clear, tokens.accentSecondary.opacity(isLit ? 0.9 : 0.22), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: isLit ? 2 : 1)
                .overlay {
                    if isLit {
                        Capsule()
                            .fill(tokens.accentSecondary)
                            .frame(width: 22, height: 3)
                            .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 4)
                    }
                }
            }
        }
        .shadow(color: isLit ? tokens.accentSecondary.opacity(0.7) : .clear, radius: 5)
        .frame(
            width: axis == .horizontal ? gap : nil,
            height: axis == .vertical ? gap : nil
        )
        .contentShape(Rectangle().inset(by: -2))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpace))
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
                (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.12), value: isLit)
    }
}
