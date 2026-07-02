import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One Block: a floating, rounded panel over the sky — HUD header (neon
/// tile art, Exo 2 title, magnify, styled ×) above the hosted app content.
/// Still strictly tiled (no overlap or z-order); the focused Block wears
/// targeting brackets and an accent glow, unfocused Blocks dim slightly.
/// WaveTerm-style management: drag the header onto another Block's edge to
/// re-split there; magnify zooms this Block to the full canvas.
struct BlockView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let block: Block
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    @State private var hasArrived = false
    @State private var isHoveringClose = false
    @State private var isHoveringMagnify = false
    @State private var dropEdge: BlockDropEdge?
    @State private var blockSize: CGSize = .zero

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
        .overlay(dropZoneHighlight(tokens: tokens))
        .shadow(color: isFocused ? tokens.accentPrimary.opacity(0.28) : .black.opacity(0.25), radius: isFocused ? 22 : 12)
        .opacity(isFocused ? 1 : 0.92)
        .scaleEffect(hasArrived || reduceMotion ? 1 : 0.97)
        .contentShape(Rectangle())
        .onTapGesture { tileLayout.focus(block.id) }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: BlockSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(BlockSizePreferenceKey.self) { blockSize = $0 }
        .onDrop(of: [.text], delegate: BlockDropDelegate(
            targetBlockID: block.id,
            tileLayout: tileLayout,
            size: { blockSize },
            edge: $dropEdge
        ))
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.12), value: dropEdge)
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

    // MARK: - Drop zones

    /// The half of this Block a dragged Block would occupy, lit in the
    /// targeting language while a drag hovers over it.
    @ViewBuilder
    private func dropZoneHighlight(tokens: DesignTokens) -> some View {
        if let dropEdge {
            let zone = RoundedRectangle(cornerRadius: 10)
                .fill(tokens.accentPrimary.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(tokens.accentSecondary.opacity(0.7), lineWidth: 1)
                )
                .overlay(
                    TargetingBrackets(length: 8)
                        .stroke(tokens.accentSecondary.opacity(0.9), lineWidth: 1.5)
                        .padding(3)
                )
                .padding(3)

            switch dropEdge {
            case .leading:
                zone.frame(width: max(blockSize.width / 2, 0)).frame(maxWidth: .infinity, alignment: .leading)
            case .trailing:
                zone.frame(width: max(blockSize.width / 2, 0)).frame(maxWidth: .infinity, alignment: .trailing)
            case .top:
                zone.frame(height: max(blockSize.height / 2, 0)).frame(maxHeight: .infinity, alignment: .top)
            case .bottom:
                zone.frame(height: max(blockSize.height / 2, 0)).frame(maxHeight: .infinity, alignment: .bottom)
            }
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

private struct BlockSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Routes a dragged Block onto this Block's nearest edge: tracks which
/// half the pointer is over (for the highlight) and performs the tree move
/// on drop.
private struct BlockDropDelegate: DropDelegate {
    let targetBlockID: UUID
    let tileLayout: TileLayout
    let size: () -> CGSize
    @Binding var edge: BlockDropEdge?

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
        defer {
            edge = nil
            tileLayout.draggingBlockID = nil
        }
        guard let dragging = tileLayout.draggingBlockID,
              let edge = edge ?? nearestEdge(to: info.location) as BlockDropEdge? else { return false }
        tileLayout.move(dragging, to: targetBlockID, edge: edge)
        return true
    }

    private func nearestEdge(to location: CGPoint) -> BlockDropEdge {
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
