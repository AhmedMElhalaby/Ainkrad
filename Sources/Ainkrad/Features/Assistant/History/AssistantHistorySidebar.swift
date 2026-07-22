import AinkradAppKit
import SwiftUI

struct AssistantHistorySidebar: View {
    let store: AssistantSessionStore
    let tokens: DesignTokens
    var onNewChat: () -> Void
    var onSelect: (UUID) -> Void

    @State private var query = ""
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.results(for: query)) { session in
                        row(session)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(12)
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(tokens.surfaceElevated.opacity(0.25))
    }

    private var header: some View {
        HStack {
            Text("HISTORY")
                .font(AinkradFont.display(11, weight: .medium)).kerning(1.5)
                .foregroundStyle(tokens.foreground.opacity(0.5))
            Spacer()
            HoverNewChatButton(tokens: tokens, action: onNewChat)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11)).foregroundStyle(tokens.foreground.opacity(0.4))
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.9))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.4)))
    }

    private func row(_ session: SavedSession) -> some View {
        HistoryRow(session: session,
                   isActive: session.id == store.activeID,
                   tokens: tokens,
                   onSelect: { onSelect(session.id) },
                   onDelete: { store.delete(session.id) })
    }
}

private struct HoverNewChatButton: View {
    let tokens: DesignTokens
    var action: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12))
                .foregroundStyle(tokens.foreground.opacity(isHovering ? 0.9 : 0.6))
                .padding(6)
                .background(Circle().fill(tokens.surfaceElevated.opacity(isHovering ? 0.75 : 0.5)))
        }
        .buttonStyle(.plain)
        .help("New chat")
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}

private struct HistoryRow: View {
    let session: SavedSession
    let isActive: Bool
    let tokens: DesignTokens
    var onSelect: () -> Void
    var onDelete: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title.isEmpty ? "New chat" : session.title)
                            .font(AinkradFont.display(12))
                            .foregroundStyle(tokens.foreground.opacity(isActive ? 1 : 0.75))
                            .lineLimit(1)
                        Text(session.updatedAt, format: .relative(presentation: .named))
                            .font(AinkradFont.mono(10))
                            .foregroundStyle(tokens.foreground.opacity(0.4))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(ChamferShape(cut: AinkradRadius.sm)
                    .fill(tokens.accentPrimary.opacity(isActive ? 0.16 : (isHovering ? 0.08 : 0))))
            }
            .buttonStyle(.plain)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(tokens.accentTertiary.opacity(0.9))
                        .padding(.trailing, 9)
                }
                .buttonStyle(.plain)
                .help("Delete chat")
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}
