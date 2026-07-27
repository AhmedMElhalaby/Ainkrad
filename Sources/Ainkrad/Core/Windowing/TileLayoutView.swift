import SwiftUI
import AppKit
import AinkradAppKit
import AinkradHostRuntime

private struct PaneResizesImmediatelyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by the layout on the pane that fills the Focus-Mode canvas, so
    /// that pane's content can resize immediately (no debounce) instead of
    /// waiting for the trailing-debounce every other pane uses. App-agnostic:
    /// any pane's content may read this, not just Terminal's.
    var paneResizesImmediately: Bool {
        get { self[PaneResizesImmediatelyKey.self] }
        set { self[PaneResizesImmediatelyKey.self] = newValue }
    }
}

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

    /// A one-shot zoom for the focused pane on a Focus toggle: it pops from
    /// this scale back to 1. A *scale* (not a frame morph) so the terminal's
    /// cols/rows never change mid-animation — the size still snaps in one step
    /// (one clean reflow), while the pane visually grows into place.
    @State private var focusPop: CGFloat = 1

    private var tileLayout: TileLayout { workspace.tileLayout }

    /// True when any pane declares a translucent window fill (via its
    /// `RegisteredApp.chromeFill` alpha) — then the shared blurred backdrop is
    /// rendered behind the panes. App-agnostic: no per-app settings read.
    private var hasTranslucentPane: Bool {
        tileLayout.blocks.contains { block in
            guard let app = registry.allApps.first(where: { $0.id == block.appID }),
                  let fill = app.chromeFill() else { return false }
            return NSColor(fill).alphaComponent < 1
        }
    }

    var body: some View {
        if tileLayout.isEmpty {
            EmptyWorkspaceView(isActiveWorkspace: workspace.id == environment.workspaceManager.activeWorkspaceID)
        } else {
            HStack(spacing: 0) {
                paneCanvas

                if workspace.viewMode == .focus, tileLayout.blocks.count > 1 {
                    FocusSwitcherRail(workspace: workspace)
                        .padding(.leading, AinkradSpacing.sm)
                        // Only the rail fades in/out; the panes must NOT
                        // animate their size on a Focus toggle (that flood of
                        // intermediate resizes duplicates terminal output).
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: workspace.viewMode)
                }
            }
            .padding([.horizontal, .bottom], AinkradSpacing.sm)
            .padding(.top, AinkradSpacing.xs)
        }
    }

    private var paneCanvas: some View {
        GeometryReader { proxy in
            // Always compute the normal split geometry. Focus Mode is handled
            // in the view (below) WITHOUT collapsing panes to zero size —
            // zero-resizing a terminal corrupts/duplicates its output.
            let geometry = tileLayout.paneGeometry(in: proxy.size, gap: AinkradSpacing.sm, collapseTo: nil)
            let inFocus = workspace.viewMode == .focus && tileLayout.blocks.count > 1
            let focusedID = tileLayout.focusedBlockID
            let fullRect = CGRect(origin: .zero, size: proxy.size)

            ZStack(alignment: .topLeading) {
                // One shared workspace backdrop behind every pane, so
                // translucent terminals reveal slices of a SINGLE blurred
                // island rather than each carrying its own. Only present when
                // transparency is enabled (otherwise opaque panes cover it).
                if hasTranslucentPane {
                    workspaceBackdrop
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                // One stable view per panel — identity is the Block id, so
                // moves/splits/closes reposition instead of re-creating.
                // `.position` (not `.offset`) so the layout/hit-test frame
                // tracks where the pane is drawn.
                //
                // In Focus Mode EVERY pane sits at full-canvas size — only the
                // focused one is shown. Holding them all full (rather than at
                // their split frame) makes switching the active pane a pure
                // visibility swap: no resize, so no reflow lag/flash on switch.
                // Panes resize once on entering/leaving Focus, never on switch.
                ForEach(tileLayout.blocks) { (block: Block) in
                    let normalFrame = geometry.frames[block.id] ?? .zero
                    let isFocusedPane = block.id == focusedID
                    let frame = inFocus ? fullRect : normalFrame
                    let isVisible = inFocus
                        ? isFocusedPane
                        : (normalFrame.width >= 1 && normalFrame.height >= 1)
                    BlockView(block: block, tileLayout: tileLayout, registry: registry, workspace: workspace, paneSize: frame.size)
                        // The focused Focus-Mode pane resizes immediately (no
                        // debounce) so its tile→full grow fills without an empty
                        // flash; all other panes keep the trailing debounce.
                        .environment(\.paneResizesImmediately, inFocus && isFocusedPane)
                        // Generation 8: the HOST says which pane is active.
                        // Plugins previously had to infer it — Terminal bound
                        // the agent's context to whichever pane was created
                        // last, so with two terminals open the assistant read
                        // the wrong buffer, silently. Only the host knows: it
                        // owns the layout, the focused id, focus mode and
                        // workspace switching.
                        .environment(\.ainkradPaneIsFocused, isFocusedPane)
                        // Every VISIBLE pane zooms into place on a Focus toggle
                        // (scale-pop, driven by `focusPop`): entering, that's the
                        // one focused pane; exiting, it's the whole split grid
                        // popping back. Scale is a render transform — it never
                        // changes the terminal's cols/rows, so the size still
                        // resizes exactly once (no empty-space-then-snap).
                        .scaleEffect(isVisible ? focusPop : 1)
                        .opacity(isVisible ? 1 : 0)
                        .frame(width: max(frame.width, 0), height: max(frame.height, 0))
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(isVisible)
                }

                if !inFocus {
                    ForEach(geometry.seams) { seam in
                        SeamView(placement: seam, tileLayout: tileLayout)
                            .frame(width: seam.frame.width, height: seam.frame.height)
                            .position(x: seam.frame.midX, y: seam.frame.midY)
                    }
                }
            }
            .coordinateSpace(name: "pane-canvas")
            // Zoom the now-visible pane(s) in on EVERY Focus toggle — entering
            // and exiting. The size has already snapped in this same update;
            // we set the start scale, then spring it to 1 on the next tick (so
            // the start frame actually renders first), animating only the scale.
            .onChange(of: workspace.viewMode) { _, _ in
                popFocusedPane()
            }
            // Switching the active pane WHILE in Focus Mode swaps which pane
            // fills the canvas — zoom the newcomer in too. In Split Mode a focus
            // change only moves the glow (no resize), so it gets no pop.
            .onChange(of: tileLayout.focusedBlockID) { _, _ in
                guard workspace.viewMode == .focus else { return }
                popFocusedPane()
            }
        }
    }

    /// Zooms the now-visible pane(s) in: set the start scale, then spring it to
    /// 1 on the next tick (so the start frame renders first), animating only the
    /// scale — the pane size has already snapped, so the terminal never reflows
    /// mid-animation.
    private func popFocusedPane() {
        focusPop = 0.92
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                focusPop = 1
            }
        }
    }

    /// The backdrop revealed through any translucent pane. It deliberately does
    /// NOT paint an opaque base: the global `AmbientSkyView` (sky + live motion)
    /// is already mounted behind the whole carousel, so leaving this layer
    /// transparent lets that living scene show through. In front of the sky it
    /// renders the real `FloatingIslandView` — framed exactly like the empty
    /// workspace — so a translucent pane reveals the SAME island a user sees on
    /// an empty workspace, not a static blurred stand-in. A single faint scrim
    /// keeps pane content legible over a busy sky.
    private var workspaceBackdrop: some View {
        let tokens = environment.themeManager.tokens
        return ZStack {
            // Match the empty workspace's island placement. There the island is
            // the top child of a centered stack that also holds the shortcut
            // hints below it, so the island sits ABOVE the geometric center.
            // Centering the island alone would drop it lower, making it appear
            // to "slide down" when a pane opens — so reserve the same hint
            // footprint (~two hint rows + their top padding) beneath it, keeping
            // the revealed island at the exact height it has on the main screen.
            VStack(spacing: 0) {
                FloatingIslandView()
                    .frame(maxWidth: 860, maxHeight: 574)
                Color.clear.frame(height: 72)
            }
            // Legibility scrim only — low enough that motion clearly shows
            // through, high enough that text over a busy sky stays readable.
            // Tuned during screenshot review.
            tokens.background.opacity(0.12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            ChamferShape(cut: AinkradRadius.sm)
                                .fill(isFocused ? tokens.accentPrimary.opacity(0.16) : tokens.surface.opacity(0.6))
                        )
                        .overlay(
                            ChamferShape(cut: AinkradRadius.sm)
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

    private func chipContent(_ block: Block, tokens: DesignTokens) -> some View {
        let symbol = environment.registry.allApps.first(where: { $0.id == block.appID })?.icon ?? "app"
        return NeonAppTile(symbol: symbol, tokens: tokens, size: 26)
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
