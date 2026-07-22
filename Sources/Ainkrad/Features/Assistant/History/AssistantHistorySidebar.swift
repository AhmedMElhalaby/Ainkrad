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
            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foreground.opacity(0.7))
                    .padding(6)
                    .background(Circle().fill(tokens.surfaceElevated.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .help("New chat")
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

private struct HistoryRow: View {
    let session: SavedSession
    let isActive: Bool
    let tokens: DesignTokens
    var onSelect: () -> Void
    var onDelete: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(session.title.isEmpty ? "New chat" : session.title)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(isActive ? 1 : 0.75))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(tokens.accentTertiary.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .help("Delete chat")
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(ChamferShape(cut: AinkradRadius.sm)
                .fill(tokens.accentPrimary.opacity(isActive ? 0.16 : (isHovering ? 0.08 : 0))))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}
