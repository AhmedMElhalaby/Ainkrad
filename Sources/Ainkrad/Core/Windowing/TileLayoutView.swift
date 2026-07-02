import SwiftUI
import AppKit

/// One tab's content: its pane tree in Split Mode, or Focus Mode — the
/// focused panel filling the canvas (the tree collapses toward it without
/// being modified) with the other panels reachable from a compact side
/// strip. Empty tabs show the island empty state.
struct TabContentView: View {
    let tab: WorkspaceTab
    let registry: BuiltInAppRegistry

    var body: some View {
        if tab.tileLayout.isEmpty {
            EmptyWorkspaceView()
        } else if let root = tab.tileLayout.root {
            HStack(spacing: 0) {
                PaneTreeView(
                    node: root,
                    path: [],
                    tileLayout: tab.tileLayout,
                    registry: registry,
                    collapseTo: tab.viewMode == .focus ? tab.tileLayout.focusedBlockID : nil,
                    tab: tab
                )

                if tab.viewMode == .focus, tab.tileLayout.blocks.count > 1 {
                    FocusSideStrip(tab: tab)
                        .padding(.leading, 8)
                }
            }
            .padding([.horizontal, .bottom], 10)
            .padding(.top, 4)
            .animation(.easeInOut(duration: 0.2), value: tab.viewMode)
            .animation(.easeInOut(duration: 0.2), value: tab.viewMode == .focus ? tab.tileLayout.focusedBlockID : nil)
            .animation(.easeOut(duration: 0.18), value: tab.tileLayout.appIDs)
        }
    }
}

/// Focus Mode's compact rail: one chip per panel, the focused one wearing
/// targeting brackets; clicking a chip brings that panel to the front.
private struct FocusSideStrip: View {
    @Environment(AppEnvironment.self) private var environment
    let tab: WorkspaceTab

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(spacing: 8) {
            ForEach(tab.tileLayout.blocks) { block in
                let isFocused = tab.tileLayout.focusedBlockID == block.id

                Button {
                    tab.tileLayout.focus(block.id)
                } label: {
                    chipContent(block, tokens: tokens)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isFocused ? tokens.accentPrimary.opacity(0.16) : tokens.surface.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isFocused ? tokens.accentPrimary.opacity(0.5) : tokens.foreground.opacity(0.1), lineWidth: 1)
                        )
                        .overlay(
                            TargetingBrackets(length: 6)
                                .stroke(isFocused ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.2)
                                .padding(-1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(block.title ?? environment.registry.allApps.first(where: { $0.id == block.appID })?.displayName ?? block.appID)
            }

            Spacer()

            Button {
                tab.viewMode = .split
                environment.workspaceManager.persist()
            } label: {
                Image(systemName: "rectangle.split.2x2")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foreground.opacity(0.55))
                    .frame(width: 36, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to Split Mode (⌘M)")
        }
        .frame(width: 44)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func chipContent(_ block: Block, tokens: DesignTokens) -> some View {
        let assetName = "AppTile-\(block.appID)-\(environment.themeManager.currentTheme.rawValue)"

        if NSImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
        } else {
            Image(systemName: environment.registry.allApps.first(where: { $0.id == block.appID })?.icon ?? "app")
                .font(.system(size: 12))
                .foregroundStyle(tokens.accentSecondary)
        }
    }
}

/// Recursively renders one node of the N-ary split tree: a pane for a
/// leaf, or children laid along the container's axis with energy seams
/// between them. When `collapseTo` is set (Focus Mode), every container
/// gives that pane's subtree 100% and collapses the rest to zero — still
/// mounted, so sessions keep running; the stored tree is untouched.
struct PaneTreeView: View {
    let node: PaneNode
    let path: [Int]
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry
    var collapseTo: UUID?
    var tab: WorkspaceTab?

    var body: some View {
        switch node {
        case .leaf(let block):
            BlockView(block: block, tileLayout: tileLayout, registry: registry, tab: tab)
        case .split(let axis, let children, let fractions):
            container(axis: axis, children: children, fractions: fractions)
        }
    }

    private func container(axis: PaneAxis, children: [PaneNode], fractions: [Double]) -> some View {
        GeometryReader { proxy in
            let isCollapsing = collapseTo != nil
            let gap: CGFloat = isCollapsing ? 0 : 8
            let effective = effectiveFractions(children: children, fractions: fractions)
            let total = axis == .horizontal ? proxy.size.width : proxy.size.height
            let available = max(total - CGFloat(children.count - 1) * gap, 0)
            let spaceName = "pane-container-\(path.map(String.init).joined(separator: "."))"

            let stack = axis == .horizontal
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))

            stack {
                ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                    PaneTreeView(
                        node: child,
                        path: path + [index],
                        tileLayout: tileLayout,
                        registry: registry,
                        collapseTo: collapseTo,
                        tab: tab
                    )
                    .frame(
                        width: axis == .horizontal ? available * effective[index] : nil,
                        height: axis == .vertical ? available * effective[index] : nil
                    )

                    if index < children.count - 1 {
                        SeamView(
                            axis: axis,
                            gap: gap,
                            isDisabled: isCollapsing,
                            coordinateSpace: spaceName
                        ) { location in
                            let position = axis == .horizontal
                                ? location.x / max(proxy.size.width, 1)
                                : location.y / max(proxy.size.height, 1)
                            tileLayout.setBoundary(path: path, after: index, to: position)
                        } onCommit: {
                            tileLayout.onStructuralChange?()
                        }
                    }
                }
            }
            .coordinateSpace(name: spaceName)
        }
    }

    private func effectiveFractions(children: [PaneNode], fractions: [Double]) -> [Double] {
        if let collapseTo {
            return children.map { tileLayout.subtreeContains(collapseTo, in: $0) ? 1.0 : 0.0 }
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
    var onCommit: () -> Void = {}

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        let tokens = environment.themeManager.tokens
        let isLit = (isHovering || isDragging) && !isDisabled

        Group {
            if axis == .horizontal {
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
                .onEnded { _ in
                    isDragging = false
                    onCommit()
                }
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
