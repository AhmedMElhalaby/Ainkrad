import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One panel: a floating, rounded pane over the sky — HUD header (neon
/// tile art, Exo 2 title, focus-mode toggle, styled ×) above the hosted
/// app content. Strictly tiled (no overlap or z-order); the focused panel
/// wears targeting brackets and an accent glow, unfocused ones dim
/// slightly. Drag the header onto another panel's edge to re-split there;
/// the header's context menu carries split/duplicate/rename/move/close.
struct BlockView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let block: Block
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry
    var tab: WorkspaceTab?

    @State private var hasArrived = false
    @State private var isHoveringClose = false
    @State private var isHoveringMagnify = false
    @State private var dropEdge: PaneEdge?
    @State private var paneSize: CGSize = .zero
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    private var app: BuiltInApp.Type? {
        registry.allApps.first { $0.id == block.appID }
    }

    private var displayName: String {
        block.title ?? app?.displayName ?? block.appID
    }

    private var isFocused: Bool {
        tileLayout.focusedBlockID == block.id
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
        .background(tokens.surface.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isFocused ? tokens.accentPrimary.opacity(0.55) : tokens.foreground.opacity(0.1),
                    lineWidth: 1
                )
        )
        .overlay(
            TargetingBrackets(length: 10)
                .stroke(isFocused ? tokens.accentSecondary.opacity(0.85) : .clear, lineWidth: 1.5)
                .padding(-2)
        )
        .overlay(dropZoneHighlight(tokens: tokens))
        .shadow(color: isFocused ? tokens.accentPrimary.opacity(0.28) : .black.opacity(0.25), radius: isFocused ? 22 : 12)
        .opacity(isFocused ? 1 : 0.92)
        .scaleEffect(hasArrived || reduceMotion ? 1 : 0.97)
        .contentShape(Rectangle())
        .onTapGesture { tileLayout.focus(block.id) }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PaneSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PaneSizePreferenceKey.self) { paneSize = $0 }
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

    /// The half of this pane the dragged pane would occupy, tinted while a
    /// drag hovers over it — the Termius drop indicator, in our accents.
    @ViewBuilder
    private func dropZoneHighlight(tokens: DesignTokens) -> some View {
        if let dropEdge {
            let zone = RoundedRectangle(cornerRadius: 10)
                .fill(tokens.accentPrimary.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(tokens.accentSecondary.opacity(0.6), lineWidth: 1)
                )
                .padding(3)

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
    }

    // MARK: - Header

    private func header(tokens: DesignTokens) -> some View {
        HStack(spacing: 8) {
            headerTile(tokens: tokens)

            if isRenaming {
                TextField("Name", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground)
                    .frame(maxWidth: 160)
                    .focused($renameFocused)
                    .onSubmit { commitRename() }
                    .onKeyPress(.escape) { isRenaming = false; return .handled }
            } else {
                Text(displayName)
                    .font(AinkradFont.display(12, weight: .medium))
                    .kerning(0.5)
                    .foregroundStyle(tokens.foreground.opacity(isFocused ? 0.95 : 0.55))
                    .lineLimit(1)
            }

            Spacer()

            if let tab, tileLayout.appIDs.count > 1 {
                let inFocusMode = tab.viewMode == .focus
                Button {
                    tileLayout.focus(block.id)
                    tab.viewMode = inFocusMode ? .split : .focus
                    environment.workspaceManager.persist()
                } label: {
                    Image(systemName: inFocusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(inFocusMode ? tokens.accentSecondary : tokens.foreground.opacity(isHoveringMagnify ? 0.95 : 0.5))
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(tokens.surfaceElevated.opacity(isHoveringMagnify ? 0.9 : 0))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringMagnify = $0 }
                .help(inFocusMode ? "Back to Split Mode (⌘M)" : "Focus Mode (⌘M)")
            }

            Button {
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
        .background(isFocused ? tokens.surfaceElevated.opacity(0.65) : .clear)
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
        .contextMenu { headerContextMenu }
    }

    @ViewBuilder
    private var headerContextMenu: some View {
        Button("Split Right") { tileLayout.split(block.id, edge: .trailing) }
            .keyboardShortcut("d", modifiers: .command)
        Button("Split Down") { tileLayout.split(block.id, edge: .bottom) }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Duplicate") { tileLayout.duplicate(block.id) }
        Button("Rename…") {
            renameDraft = displayName
            isRenaming = true
            renameFocused = true
        }
        if let tab {
            let workspace = environment.workspaceManager.activeWorkspace
            Menu("Move to Tab") {
                ForEach(workspace.tabs.filter { $0.id != tab.id }) { destination in
                    Button(destination.name) {
                        workspace.movePanel(block.id, from: tab, to: destination)
                    }
                }
                Divider()
                Button("New Tab") {
                    let destination = workspace.addTab()
                    workspace.movePanel(block.id, from: tab, to: destination)
                }
            }
        }
        Divider()
        Button("Reset Layout") { tileLayout.resetLayout() }
        Button("Close", role: .destructive) { tileLayout.close(block.id) }
            .keyboardShortcut("w", modifiers: .command)
    }

    private func commitRename() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        block.title = trimmed.isEmpty ? nil : trimmed
        isRenaming = false
        environment.workspaceManager.persist()
    }

    /// The app's neon tile artwork at HUD size, matching the Launcher rows;
    /// falls back to the themed SF Symbol mini-tile.
    @ViewBuilder
    private func headerTile(tokens: DesignTokens) -> some View {
        let assetName = "AppTile-\(block.appID)-\(environment.themeManager.currentTheme.rawValue)"

        if NSImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .opacity(isFocused ? 1 : 0.65)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(tokens.surfaceElevated)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: app?.icon ?? "app")
                        .font(.system(size: 9))
                        .foregroundStyle(tokens.accentSecondary.opacity(isFocused ? 1 : 0.65))
                )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(tokens: DesignTokens) -> some View {
        if let app {
            app.makeRootView()
                .padding(6)
        } else {
            tokens.surface
        }
    }
}

private struct PaneSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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
