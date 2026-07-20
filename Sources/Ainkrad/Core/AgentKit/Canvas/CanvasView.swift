import SwiftUI
import AinkradAppKit

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
                        .frame(width: element.rect.width, height: element.rect.height)
                        .offset(x: element.rect.x, y: element.rect.y)
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
                        let base = dragStart ?? element.rect
                        store.bringToFront(id: element.id)
                        store.move(id: element.id,
                                   to: CGPoint(x: base.x + v.translation.width,
                                               y: base.y + v.translation.height))
                    }
            )
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
                        store.resize(id: element.id,
                                     to: CGSize(width: max(160, base.width + v.translation.width),
                                                height: max(100, base.height + v.translation.height)))
                    }
            )
    }
}
