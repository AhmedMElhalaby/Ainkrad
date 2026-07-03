import SwiftUI
import AppKit

/// One workspace's content: its pane tree in Split Mode, or Focus Mode —
/// the focused panel filling the canvas with the other panels reachable
/// from a compact switcher rail. Empty workspaces show the island empty
/// state.
///
/// RENDERING CONTRACT: every panel renders exactly once, in a flat layer
/// keyed by its stable Block id; the layout tree only computes frames
/// (see `paneGeometry`). Structural changes therefore MOVE views instead
/// of re-creating them — a dragged terminal keeps its live session.
struct TileLayoutView: View {
    @Environment(AppEnvironment.self) private var environment
    let workspace: Workspace
    let registry: BuiltInAppRegistry

    private var tileLayout: TileLayout { workspace.tileLayout }

    var body: some View {
        if tileLayout.isEmpty {
            EmptyWorkspaceView()
        } else {
            HStack(spacing: 0) {
                paneCanvas

                if workspace.viewMode == .focus, tileLayout.blocks.count > 1 {
                    FocusSwitcherRail(workspace: workspace)
                        .padding(.leading, 8)
                }
            }
            .padding([.horizontal, .bottom], 10)
            .padding(.top, 4)
            .animation(.easeInOut(duration: 0.2), value: workspace.viewMode)
        }
    }

    private var paneCanvas: some View {
        GeometryReader { proxy in
            let collapseTo = workspace.viewMode == .focus ? tileLayout.focusedBlockID : nil
            let geometry = tileLayout.paneGeometry(in: proxy.size, gap: 8, collapseTo: collapseTo)

            ZStack(alignment: .topLeading) {
                // One shared workspace backdrop behind every pane, so
                // translucent terminals reveal slices of a SINGLE blurred
                // island rather than each carrying its own. Only present when
                // transparency is enabled (otherwise opaque panes cover it).
                if environment.terminalSettingsStore.settings.backgroundOpacity < 1 {
                    workspaceBackdrop
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                // One stable view per panel — identity is the Block id, so
                // moves/splits/closes reposition instead of re-creating.
                // `.position` (not `.offset`) so the layout/hit-test frame
                // tracks where the pane is drawn — otherwise every pane's
                // drop & tap region stays pinned at the top-leading corner
                // and drag-to-rearrange targets the wrong pane.
                ForEach(tileLayout.blocks) { block in
                    let frame = geometry.frames[block.id] ?? .zero
                    let isVisible = frame.width >= 1 && frame.height >= 1
                    BlockView(block: block, tileLayout: tileLayout, registry: registry, workspace: workspace, paneSize: frame.size)
                        .frame(width: max(frame.width, 0), height: max(frame.height, 0))
                        .position(x: frame.midX, y: frame.midY)
                        .opacity(isVisible ? 1 : 0)
                        .allowsHitTesting(isVisible)
                }

                ForEach(geometry.seams) { seam in
                    SeamView(placement: seam, tileLayout: tileLayout)
                        .frame(width: seam.frame.width, height: seam.frame.height)
                        .position(x: seam.frame.midX, y: seam.frame.midY)
                }
            }
            .coordinateSpace(name: "pane-canvas")
            .animation(
                .spring(response: 0.32, dampingFraction: 0.82),
                value: structureSignature
            )
        }
    }

    /// The single blurred floating island shared by the whole workspace —
    /// revealed through translucent terminals (all panes see the same image,
    /// so it reads as one background with the windows floating on top).
    private var workspaceBackdrop: some View {
        let tokens = environment.themeManager.tokens
        return ZStack {
            tokens.background
            Image(islandAsset)
                .resizable()
                .scaledToFit()
                .blur(radius: 30)
                .padding(40)
        }
    }

    /// Island art ships in two accents; new themes use the nearer one.
    private var islandAsset: String {
        switch environment.themeManager.currentTheme {
        case .cyberPurple, .dracula, .tokyoNight: return "Island-CyberPurple"
        default: return "Island-NeonBlue"
        }
    }

    /// Frame changes animate only when the STRUCTURE changes (move, open,
    /// close, mode toggle) — seam drags mutate fractions without touching
    /// this signature, so resizing stays direct and un-animated.
    private var structureSignature: String {
        let order = tileLayout.blocks.map { $0.id.uuidString }.joined(separator: ",")
        let mode = workspace.viewMode == .focus ? (tileLayout.focusedBlockID?.uuidString ?? "") : "split"
        return order + "|" + mode
    }
}

/// Focus Mode's compact switcher: one chip per panel (not a tab bar), the
/// focused one wearing targeting brackets; clicking a chip brings that
/// panel forward.
private struct FocusSwitcherRail: View {
    @Environment(AppEnvironment.self) private var environment
    let workspace: Workspace

    var body: some View {
        let tokens = environment.themeManager.tokens
        let tileLayout = workspace.tileLayout

        VStack(spacing: 8) {
            ForEach(tileLayout.blocks) { block in
                let isFocused = tileLayout.focusedBlockID == block.id

                Button {
                    tileLayout.focus(block.id)
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
                .help(environment.registry.allApps.first(where: { $0.id == block.appID })?.displayName ?? block.appID)
            }

            Spacer()

            Button {
                workspace.viewMode = .split
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

/// An energy seam between sibling panes, absolutely positioned by its
/// `SeamPlacement`: a thin accent gradient line in the gap, with a grabber
/// capsule that brightens on hover and while dragging to resize.
private struct SeamView: View {
    @Environment(AppEnvironment.self) private var environment
    let placement: SeamPlacement
    let tileLayout: TileLayout

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        let tokens = environment.themeManager.tokens
        let isLit = isHovering || isDragging

        Group {
            if placement.axis == .horizontal {
                LinearGradient(
                    colors: [.clear, tokens.accentSecondary.opacity(isLit ? 0.9 : 0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: isLit ? 2 : 1)
                .frame(maxWidth: .infinity)
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
                .frame(maxHeight: .infinity)
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
        // Grab target is wider than the 1px seam so the boundary is easy to
        // catch with the mouse without hunting for a hairline.
        .contentShape(Rectangle().inset(by: -6))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("pane-canvas"))
                .onChanged { value in
                    isDragging = true
                    let location = placement.axis == .horizontal ? value.location.x : value.location.y
                    let position = (location - placement.containerOrigin) / max(placement.containerLength, 1)
                    tileLayout.setBoundary(path: placement.path, after: placement.index, to: position)
                }
                .onEnded { _ in
                    isDragging = false
                    tileLayout.onStructuralChange?()
                }
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                (placement.axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.12), value: isLit)
    }
}
