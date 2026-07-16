import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AinkradAppKit

/// One pane: a floating, rounded panel over the sky — HUD header (neon
/// tile art, Exo 2 title, magnify, styled ×) above the hosted app content.
/// Strictly tiled in the balanced grid (no overlap or z-order); the
/// focused pane wears targeting brackets and an accent glow, unfocused
/// panes dim slightly. Termius-style management: drag the header over
/// another pane to change position (the grid reflows live); magnify zooms
/// this pane to the full canvas.
struct BlockView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let block: Block
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry
    var workspace: Workspace?
    /// The pane's exact pixel size, supplied by the layout (see
    /// `paneGeometry`). Feeding it in directly — rather than reading it back
    /// through a preference key — keeps the drop delegate's edge math from
    /// ever seeing a stale zero size (which would force every drop to the
    /// `.trailing` fallback, making perpendicular splits impossible).
    var paneSize: CGSize = .zero

    @State private var hasArrived = false
    @State private var isHoveringClose = false
    @State private var isHoveringMagnify = false
    @State private var dropEdge: PaneEdge?

    private var app: RegisteredApp? {
        registry.allApps.first { $0.id == block.appID }
    }

    private var isFocused: Bool {
        tileLayout.focusedBlockID == block.id
    }

    /// The pane is translucent when its app declares a sub-opaque window fill
    /// (Assistant opacity slider, Terminal scheme opacity, Git Mage transparency).
    private var isTranslucentPane: Bool {
        guard let fill = app?.chromeFill() else { return false }
        return NSColor(fill).alphaComponent < 1
    }

    /// Render the host's blurred sky+island behind this pane only when the app's
    /// blur is enabled AND the pane is translucent (otherwise the pane content
    /// covers it — rendering would be wasted, and there'd be nothing to reveal).
    private var glassBlur: Bool {
        environment.appAppearanceStore.blurEnabled(block.appID) && isTranslucentPane
    }

    private var isInFocusMode: Bool {
        workspace?.viewMode == .focus
    }

    /// True while this pane's header drag session is live — it "lifts":
    /// dims and shrinks slightly until dropped or released.
    private var isBeingDragged: Bool {
        tileLayout.draggingBlockID == block.id
    }

    private var paneOpacity: Double {
        if isBeingDragged { return 0.45 }
        return isFocused ? 1 : 0.92
    }

    private var paneScale: CGFloat {
        if !hasArrived && !reduceMotion { return 0.97 }
        return isBeingDragged ? 0.98 : 1
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(spacing: 0) {
            header(tokens: tokens)

            LinearGradient(
                colors: [.clear, tokens.accentPrimary.opacity(isFocused ? 0.5 : 0.12), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            content(tokens: tokens)
        }
        // The pane body is clear, so a translucent app (Terminal scheme
        // opacity, Git Mage transparency, Assistant opacity) reveals whatever
        // sits behind it: the shared sharp workspace backdrop by default, or —
        // when this app's blur is enabled — the host-rendered Gaussian blur
        // below. A view can't blur the layers behind it, so the host draws its
        // own sky+island copy here and blurs that. It sits behind the WHOLE
        // pane (header + content), so the two frost continuously (no seam).
        .background {
            if glassBlur {
                ZStack {
                    AmbientSkyView()
                    FloatingIslandView()
                        .frame(maxWidth: 860, maxHeight: 574)
                }
                .blur(radius: 26)
            }
        }
        .clipShape(ChamferShape(cut: AinkradRadius.md))
        .overlay(
            ChamferShape(cut: AinkradRadius.md)
                .strokeBorder(
                    isFocused ? tokens.accentSecondary.opacity(0.55) : tokens.foreground.opacity(0.1),
                    lineWidth: 1
                )
        )
        .overlay(
            TargetingBrackets(length: 10)
                .stroke(isFocused ? tokens.accentSecondary.opacity(0.85) : .clear, lineWidth: 1.5)
                .padding(-2)
        )
        .overlay(dropZoneHighlight(tokens: tokens))
        .modifier(PaneFocusGlow(isFocused: isFocused))
        .opacity(paneOpacity)
        .scaleEffect(paneScale)
        .contentShape(Rectangle())
        .onTapGesture { tileLayout.focus(block.id) }
        .animation(.easeOut(duration: 0.15), value: isBeingDragged)
        // When the drag session ends (drop landed elsewhere, or released
        // over no target), drop any lingering preview highlight — SwiftUI
        // doesn't reliably call dropExited on panes the drag merely passed
        // over, so this is the guaranteed clear.
        .onChange(of: tileLayout.draggingBlockID) { _, newValue in
            if newValue == nil { dropEdge = nil }
        }
        .onDrop(of: [.text], delegate: PaneEdgeDropDelegate(
            targetBlockID: block.id,
            tileLayout: tileLayout,
            size: { paneSize },
            edge: $dropEdge
        ))
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.1), value: dropEdge)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.15)) { hasArrived = true }
        }
    }

    /// The half of this pane the dragged pane would occupy — a live drop
    /// preview in the targeting language: accent wash, corner brackets,
    /// and a split-direction glyph, animating between edges as the drag
    /// moves.
    @ViewBuilder
    private func dropZoneHighlight(tokens: DesignTokens) -> some View {
        // A drop preview only means anything while a drag is in flight —
        // gating on the live drag flag (which every render observes)
        // guarantees the highlight vanishes the instant the drag ends, even
        // if a stale `dropEdge` lingers from a pane the drag passed over.
        if let dropEdge, tileLayout.draggingBlockID != nil {
            let isHorizontal = dropEdge == .leading || dropEdge == .trailing
            let zone = ChamferShape(cut: AinkradRadius.sm)
                .fill(tokens.accentPrimary.opacity(0.16))
                .overlay(
                    ChamferShape(cut: AinkradRadius.sm)
                        .strokeBorder(tokens.accentSecondary.opacity(0.65), lineWidth: 1)
                )
                .overlay(
                    TargetingBrackets(length: 9)
                        .stroke(tokens.accentSecondary.opacity(0.9), lineWidth: 1.5)
                        .padding(4)
                )
                .overlay(
                    Image(systemName: isHorizontal ? "rectangle.split.2x1" : "rectangle.split.1x2")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tokens.accentSecondary.opacity(0.85))
                        .shadow(color: tokens.accentSecondary.opacity(0.8), radius: 6)
                )
                .padding(3)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            Group {
                switch dropEdge {
                case .leading:
                    zone.frame(width: max(paneSize.width / 2, 0)).frame(maxWidth: .infinity, alignment: .leading)
                case .trailing:
                    zone.frame(width: max(paneSize.width / 2, 0)).frame(maxWidth: .infinity, alignment: .trailing)
                case .top:
                    zone.frame(height: max(paneSize.height / 2, 0)).frame(maxHeight: .infinity, alignment: .top)
                case .bottom:
                    zone.frame(height: max(paneSize.height / 2, 0)).frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Header

    private func header(tokens: DesignTokens) -> some View {
        HStack(spacing: 8) {
            headerTile(tokens: tokens)

            Text(app?.displayName ?? block.appID)
                .font(AinkradFont.display(12, weight: .medium))
                .kerning(0.5)
                .foregroundStyle(tokens.foreground.opacity(isFocused ? 0.95 : 0.55))

            Spacer()

            if let workspace, tileLayout.appIDs.count > 1 {
                Button {
                    tileLayout.focus(block.id)
                    workspace.viewMode = isInFocusMode ? .split : .focus
                    environment.sounds.play(.focusMode)
                } label: {
                    Image(systemName: isInFocusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isInFocusMode ? tokens.accentSecondary : tokens.foreground.opacity(isHoveringMagnify ? 0.95 : 0.5))
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(tokens.surfaceElevated.opacity(isHoveringMagnify ? 0.9 : 0))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringMagnify = $0 }
                .help(isInFocusMode ? "Back to Split Mode (⌘M)" : "Focus Mode (⌘M)")
            }

            Button {
                environment.sounds.play(.appClose)
                tileLayout.close(block.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(isHoveringClose ? 0.95 : 0.5))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(tokens.surfaceElevated.opacity(isHoveringClose ? 0.9 : 0))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
            .help("Close (⌘W)")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(headerBackground(tokens: tokens))
        .contentShape(Rectangle())
        .onDrag {
            tileLayout.draggingBlockID = block.id
            return NSItemProvider(object: block.id.uuidString as NSString)
        } preview: {
            // Termius-style drag ghost: a small pill, not the whole pane.
            HStack(spacing: 6) {
                headerTile(tokens: tokens)
                Text(app?.displayName ?? block.appID)
                    .font(AinkradFont.display(11, weight: .medium))
                    .foregroundStyle(tokens.foreground)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tokens.surfaceElevated)
            .clipShape(Capsule())
        }
        .contextMenu {
            Button("Split Right") { tileLayout.split(block.id, edge: .trailing) }
                .keyboardShortcut("d", modifiers: .command)
            Button("Split Down") { tileLayout.split(block.id, edge: .bottom) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Duplicate") { tileLayout.duplicate(block.id) }
            Divider()
            if let workspace {
                Button(isInFocusMode ? "Back to Split Mode" : "Focus Mode") {
                    tileLayout.focus(block.id)
                    workspace.viewMode = isInFocusMode ? .split : .focus
                    environment.sounds.play(.focusMode)
                }
                .keyboardShortcut("m", modifiers: .command)
            }
            Button("Reset Layout") { tileLayout.resetLayout() }
            Divider()
            Button("Close", role: .destructive) {
                environment.sounds.play(.appClose)
                tileLayout.close(block.id)
            }
            .keyboardShortcut("w", modifiers: .command)
        }
    }

    /// The header fill. When the app declares a window fill (e.g. Terminal's
    /// scheme background at its transparency), the title bar adopts it so it's
    /// the same color and opacity as the window below — one continuous surface,
    /// revealing the same blurred island when translucent. Otherwise it falls
    /// back to the HUD surface, brighter while focused. Focus is still legible
    /// either way: the whole pane dims (`paneOpacity`) and wears the accent
    /// border/glow when unfocused.
    @ViewBuilder
    private func headerBackground(tokens: DesignTokens) -> some View {
        if let fill = app?.chromeFill() {
            fill
        } else {
            isFocused ? tokens.surfaceElevated.opacity(0.92) : tokens.surface.opacity(0.9)
        }
    }

    /// The app's neon tile at HUD size, drawn live from the active theme and
    /// matching the Launcher rows; dims when the block is unfocused.
    private func headerTile(tokens: DesignTokens) -> some View {
        NeonAppTile(symbol: app?.icon ?? "app", tokens: tokens, size: 18)
            .opacity(isFocused ? 1 : 0.65)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(tokens: DesignTokens) -> some View {
        if let app {
            // Fills the body edge-to-edge; the app provides its own background
            // (opaque, or translucent-over-blur for terminal transparency).
            app.makeRootView()
        } else {
            tokens.surface
        }
    }
}

/// Focused panes wear the shared Cardinal HUD panel glow; unfocused panes
/// keep a calm contact shadow so the grid doesn't read as flat.
private struct PaneFocusGlow: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        if isFocused {
            content.ainkradPanelGlow()
        } else {
            content.shadow(color: .black.opacity(0.25), radius: 12)
        }
    }
}

/// The Termius drop mechanism: while a dragged pane hovers, the nearest
/// half of this pane is tracked (for the highlight); dropping performs
/// `TileLayout.move` — joining as an equal sibling on parallel edges, or
/// wrapping this pane into a stacked pair on perpendicular ones.
private struct PaneEdgeDropDelegate: DropDelegate {
    let targetBlockID: UUID
    let tileLayout: TileLayout
    let size: () -> CGSize
    @Binding var edge: PaneEdge?

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging = tileLayout.draggingBlockID else { return false }
        return dragging != targetBlockID
    }

    func dropEntered(info: DropInfo) {
        edge = nearestEdge(to: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        edge = nearestEdge(to: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        edge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let landingEdge = edge ?? nearestEdge(to: info.location)
        defer {
            edge = nil
            tileLayout.draggingBlockID = nil
        }
        guard let dragging = tileLayout.draggingBlockID else { return false }
        tileLayout.move(dragging, to: targetBlockID, edge: landingEdge)
        return true
    }

    private func nearestEdge(to location: CGPoint) -> PaneEdge {
        let bounds = size()
        guard bounds.width > 0, bounds.height > 0 else { return .trailing }
        let dx = location.x / bounds.width - 0.5
        let dy = location.y / bounds.height - 0.5
        if abs(dx) > abs(dy) {
            return dx < 0 ? .leading : .trailing
        } else {
            return dy < 0 ? .top : .bottom
        }
    }
}
