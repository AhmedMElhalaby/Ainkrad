import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

    @State private var hasArrived = false
    @State private var isHoveringClose = false
    @State private var isHoveringMagnify = false

    private var app: BuiltInApp.Type? {
        registry.allApps.first { $0.id == block.appID }
    }

    private var isFocused: Bool {
        tileLayout.focusedBlockID == block.id
    }

    private var isMagnified: Bool {
        tileLayout.magnifiedBlockID == block.id
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
        .shadow(color: isFocused ? tokens.accentPrimary.opacity(0.28) : .black.opacity(0.25), radius: isFocused ? 22 : 12)
        .opacity(isFocused ? 1 : 0.92)
        .scaleEffect(hasArrived || reduceMotion ? 1 : 0.97)
        .contentShape(Rectangle())
        .onTapGesture { tileLayout.focus(block.id) }
        .onDrop(of: [.text], delegate: PaneReorderDropDelegate(
            targetBlockID: block.id,
            tileLayout: tileLayout
        ))
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.15)) { hasArrived = true }
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

            if tileLayout.appIDs.count > 1 {
                Button {
                    tileLayout.toggleMagnify(block.id)
                } label: {
                    Image(systemName: isMagnified ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isMagnified ? tokens.accentSecondary : tokens.foreground.opacity(isHoveringMagnify ? 0.95 : 0.5))
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(tokens.surfaceElevated.opacity(isHoveringMagnify ? 0.9 : 0))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringMagnify = $0 }
                .help(isMagnified ? "Restore layout (⌘⇧F)" : "Magnify (⌘⇧F)")
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
        }
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

/// Termius-style pane reordering: as the dragged pane passes over a
/// sibling, it takes that position and the grid reflows live; the drop
/// just ends the session.
private struct PaneReorderDropDelegate: DropDelegate {
    let targetBlockID: UUID
    let tileLayout: TileLayout

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging = tileLayout.draggingBlockID else { return false }
        return dragging != targetBlockID
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = tileLayout.draggingBlockID, dragging != targetBlockID,
              let from = tileLayout.blocks.firstIndex(where: { $0.id == dragging }),
              let to = tileLayout.blocks.firstIndex(where: { $0.id == targetBlockID }) else { return }

        if from < to {
            // Moving forward: land after the target.
            let successor = to + 1 < tileLayout.blocks.count ? tileLayout.blocks[to + 1].id : nil
            tileLayout.movePane(dragging, before: successor)
        } else {
            tileLayout.movePane(dragging, before: targetBlockID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        tileLayout.draggingBlockID = nil
        return true
    }
}
