import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The `/` filter, ⌘F search and ⌘P jump surface.
///
/// One view for three modes because they are the same interaction — a field
/// plus a result list — differing only in where the candidates come from.
/// Three separate palettes would be three places to keep the keyboard handling
/// consistent.
struct FilesFinderBar: View {
    @Bindable var search: FilesSearchStore
    let iconSize: CGFloat
    let onSubmit: (SearchHit) -> Void
    /// Runs the recursive walk. Separate from `onSubmit` because ⌘F's Return
    /// STARTS the search; it does not accept a result.
    let onRunSearch: () -> Void
    let onClose: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var highlighted = 0

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo

    private var showsResultList: Bool { search.mode != .filter }
    private var hits: [SearchHit] { search.rankedResults }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            field
            if showsResultList { resultList }
        }
        .padding(AinkradSpacing.md)
        .frame(width: showsResultList ? 520 : 320)
        .background(ChamferShape(cut: 8).fill(theme.surfaceElevated.opacity(0.97)))
        .onAppear { fieldFocused = true; highlighted = 0 }
        .onChange(of: search.queryText) { _, _ in highlighted = 0 }
    }

    private var field: some View {
        HStack(spacing: AinkradSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(theme.foreground.opacity(0.5))

            TextField(placeholder, text: $search.queryText)
                .textFieldStyle(.plain)
                .font(AinkradFontResolver.font(.body, typography: typo))
                .focused($fieldFocused)
                .onSubmit(submitHighlighted)
                .onExitCommand(perform: onClose)
                .onKeyPress(.downArrow) { moveHighlight(1) }
                .onKeyPress(.upArrow) { moveHighlight(-1) }

            if search.isSearching {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if hits.isEmpty && !search.queryText.isEmpty && !search.isSearching {
            Text("No matches")
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(theme.foreground.opacity(0.5))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            resultRow(hit, isHighlighted: index == highlighted)
                                .id(hit.id)
                                .onTapGesture { onSubmit(hit) }
                        }
                    }
                }
                .frame(maxHeight: 320)
                .onChange(of: highlighted) { _, index in
                    guard hits.indices.contains(index) else { return }
                    proxy.scrollTo(hits[index].id, anchor: nil)
                }
            }

            // Silent truncation would read as "that's everything" when it
            // isn't — say so.
            if search.didTruncate {
                Text("Showing the first \(hits.count) matches — narrow the search to see more.")
                    .font(AinkradFontResolver.font(.caption, typography: typo))
                    .foregroundStyle(theme.foreground.opacity(0.45))
            }
        }
    }

    private func resultRow(_ hit: SearchHit, isHighlighted: Bool) -> some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradIconGlyph(systemName: iconName(for: hit.entry), size: iconSize - 1)
                .frame(width: iconSize + 4)
            Text(hit.entry.name)
                .font(AinkradFontResolver.font(.body, typography: typo))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
            Spacer(minLength: AinkradSpacing.sm)
            // WHERE it was found is most of the value of a recursive search.
            Text(hit.relativeDirectory)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(theme.foreground.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, 4)
        .background(ChamferShape(cut: 4).fill(
            isHighlighted ? theme.accentPrimary.opacity(0.22) : .clear))
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch search.mode {
        case .filter: return "line.3.horizontal.decrease"
        case .search: return "magnifyingglass"
        case .jump: return "arrow.turn.down.right"
        case nil: return "magnifyingglass"
        }
    }

    private var placeholder: String {
        switch search.mode {
        case .filter: return "Filter this folder"
        case .search: return "Search below here — press Return"
        case .jump: return "Jump to a file"
        case nil: return ""
        }
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        guard showsResultList, !hits.isEmpty else { return .ignored }
        highlighted = min(max(0, highlighted + delta), hits.count - 1)
        return .handled
    }

    private func submitHighlighted() {
        // Search walks the disk, so the first Return RUNS it rather than
        // accepting a result — the list is empty until it has.
        if search.mode == .search, hits.isEmpty {
            onRunSearch()
            return
        }
        guard hits.indices.contains(highlighted) else { return }
        onSubmit(hits[highlighted])
    }
}
