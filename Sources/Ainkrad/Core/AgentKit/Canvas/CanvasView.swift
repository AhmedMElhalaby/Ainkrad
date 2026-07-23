import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Live Canvas: agent-rendered elements as movable/resizable layered HUD
/// cards with hover + parallax. The user can rearrange/pin/dismiss; layout
/// persists per session via `CanvasStore`. Reconstructable from the transcript.
@MainActor
struct CanvasView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    let store: CanvasStore

    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        let tokens = environment.themeManager.tokens
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let p) = phase { hoverPoint = p }
                    }

                if store.model.elements.isEmpty {
                    emptyState(tokens: tokens)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                ForEach(store.model.ordered) { element in
                    CanvasCard(element: element, store: store, tokens: tokens,
                               parallax: parallax(for: element, in: proxy.size),
                               reduceMotion: reduceMotion)
                        .zIndex(Double(element.z))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Small pointer-driven parallax per card (deeper z drifts less).
    private func parallax(for element: CanvasElement, in size: CGSize) -> CGSize {
        guard !reduceMotion, size.width > 0 else { return .zero }
        let dx = (hoverPoint.x / size.width - 0.5) * 8
        let dy = (hoverPoint.y / size.height - 0.5) * 8
        let depth = 1.0 / Double(max(1, element.z + 1))
        return CGSize(width: dx * depth, height: dy * depth)
    }

    private func emptyState(tokens: DesignTokens) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "square.on.square.dashed").font(.system(size: 26))
                .foregroundStyle(tokens.foreground.opacity(0.25))
            Text("The assistant will lay results out here")
                .font(AinkradFont.display(12)).foregroundStyle(tokens.foreground.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One draggable/resizable card wrapping a `CanvasElementView`.
@MainActor
private struct CanvasCard: View {
    let element: CanvasElement
    let store: CanvasStore
    let tokens: DesignTokens
    let parallax: CGSize
    let reduceMotion: Bool
    @State private var isHovering = false
    @GestureState private var dragStart: CanvasRect?
    @GestureState private var resizeStart: CanvasRect?
    // Perf fix (I2/M1): live-drag/resize preview state ONLY — the store is a
    // synchronous full-document atomic-write persistence layer (`CanvasStore.
    // commit`), so writing it on every `DragGesture.onChanged` tick was a disk
    // write per pixel of movement. These hold the in-flight visual delta;
    // the store is committed exactly once, in `.onEnded`.
    @State private var dragPreviewOffset: CGSize = .zero
    @State private var resizePreviewSize: CGSize?
    @State private var hasBroughtToFrontThisDrag = false

    /// The rect actually rendered: the committed `element.rect`, overlaid with
    /// any in-flight drag/resize preview. `element.rect` itself never changes
    /// mid-gesture (the store isn't written to until `.onEnded`), so it stays
    /// a stable anchor for the whole gesture.
    private var previewRect: CanvasRect {
        var r = element.rect
        r.x += dragPreviewOffset.width
        r.y += dragPreviewOffset.height
        if let size = resizePreviewSize {
            r.width = size.width
            r.height = size.height
        }
        return r
    }

    var body: some View {
        CanvasElementView(element: element, tokens: tokens)
            .overlay(alignment: .topTrailing) { if isHovering { controls } }
            .overlay(alignment: .bottomTrailing) { if isHovering { resizeHandle } }
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .offset(parallax)
            .shadow(color: tokens.accentSecondary.opacity(isHovering ? 0.18 : 0.08),
                    radius: isHovering ? 12 : 6)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: parallax)
            .gesture(
                DragGesture()
                    .updating($dragStart) { _, state, _ in
                        if state == nil { state = element.rect }
                    }
                    .onChanged { v in
                        if !hasBroughtToFrontThisDrag {
                            store.bringToFront(id: element.id)
                            hasBroughtToFrontThisDrag = true
                        }
                        dragPreviewOffset = v.translation
                    }
                    .onEnded { v in
                        let base = dragStart ?? element.rect
                        store.move(id: element.id,
                                   to: CGPoint(x: base.x + v.translation.width,
                                               y: base.y + v.translation.height))
                        dragPreviewOffset = .zero
                        hasBroughtToFrontThisDrag = false
                    }
            )
            .frame(width: previewRect.width, height: previewRect.height)
            .offset(x: previewRect.x, y: previewRect.y)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            AinkradIconButton(systemName: element.pinned ? "pin.fill" : "pin", size: 20,
                               tooltip: element.pinned ? "Unpin" : "Pin") {
                store.setPinned(id: element.id, !element.pinned)
            }
            AinkradIconButton(systemName: "xmark", size: 20, tooltip: "Dismiss") {
                store.remove(id: element.id)
            }
        }
        .padding(6)
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right").font(.system(size: 10))
            .foregroundStyle(tokens.foreground.opacity(0.4)).padding(4)
            .gesture(
                DragGesture()
                    .updating($resizeStart) { _, state, _ in
                        if state == nil { state = element.rect }
                    }
                    .onChanged { v in
                        let base = resizeStart ?? element.rect
                        resizePreviewSize = CGSize(width: max(160, base.width + v.translation.width),
                                                    height: max(100, base.height + v.translation.height))
                    }
                    .onEnded { v in
                        let base = resizeStart ?? element.rect
                        store.resize(id: element.id,
                                     to: CGSize(width: max(160, base.width + v.translation.width),
                                                height: max(100, base.height + v.translation.height)))
                        resizePreviewSize = nil
                    }
            )
    }
}
