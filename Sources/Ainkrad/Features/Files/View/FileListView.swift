import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The sortable header + scrolling rows for one tab.
struct FileListView: View {
    @Bindable var tab: FilesTab
    let iconSize: CGFloat
    let rowPadding: CGFloat
    let showMetadata: Bool
    /// Resolves a row's git state. A closure rather than the provider itself so
    /// the list stays testable and unaware of how status is fetched.
    let gitStatus: (URL) -> GitFileStatus?

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    /// Captured once, NOT a computed property: a computed `Date()` would be
    /// evaluated per row, so a 5,000-entry directory would allocate 5,000
    /// dates. Refreshed when the listing changes, which is the only time
    /// "today vs. older" can shift meaningfully.
    @State private var now = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .onChange(of: tab.currentDirectory) { _, _ in now = Date() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = tab.loadError {
            AinkradErrorState(message: error, retryTitle: "Retry") { tab.reload() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tab.visibleEntries.isEmpty {
            AinkradEmptyState(icon: "folder", title: "Empty",
                              message: "This folder has nothing to show.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(tab.visibleEntries) { entry in
                            FileRowView(
                                entry: entry,
                                isCursor: tab.cursorEntry == entry,
                                isSelected: tab.selection.contains(entry.url),
                                now: now,
                                iconSize: iconSize,
                                rowPadding: rowPadding,
                                showMetadata: showMetadata,
                                gitStatus: gitStatus(entry.url),
                                isIgnored: tab.ignoredURLs.contains(entry.url),
                                onTap: { tab.placeCursor(at: entry) },
                                onDoubleTap: { tab.descend(into: entry) }
                            )
                            .id(entry.url)
                        }
                    }
                    .padding(.horizontal, FilesColumnMetrics.rowStackInset)
                    .padding(.vertical, AinkradSpacing.xs)
                }
                .onChange(of: tab.cursorIndex) { _, _ in
                    guard let entry = tab.cursorEntry else { return }
                    // `anchor: nil` scrolls the MINIMUM distance needed to
                    // bring the row into view. Passing `.center` re-centred
                    // the whole list on every arrow press — the list lurched
                    // under you instead of scrolling at the edges.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        proxy.scrollTo(entry.url, anchor: nil)
                    }
                }
            }
        }
    }

    /// Click-to-sort column titles. No divider under the header — the design
    /// language forbids separator lines; separation reads via spacing.
    private var header: some View {
        HStack(spacing: AinkradSpacing.sm) {
            headerButton("Name", key: .name)
            Spacer(minLength: AinkradSpacing.md)
            if showMetadata {
                headerButton("Size", key: .size)
                    .frame(width: FilesColumnMetrics.sizeWidth, alignment: .trailing)
                headerButton("Modified", key: .modified)
                    .frame(width: FilesColumnMetrics.modifiedWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, FilesColumnMetrics.headerInset)
        .padding(.bottom, AinkradSpacing.xs)
    }

    private func headerButton(_ title: String, key: FileSortKey) -> some View {
        Button {
            // Mirrors `nextSort(current:column:)` from the kit: a new column
            // starts ascending, the active column toggles direction.
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                if tab.sortKey == key {
                    tab.sortAscending.toggle()
                } else {
                    tab.sortKey = key
                    tab.sortAscending = true
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(title.uppercased())
                    .font(AinkradFontResolver.font(.caption, weight: .medium, typography: typo))
                    .tracking(0.9)
                Image(systemName: "chevron.up")
                    .font(.system(size: 7, weight: .bold))
                    // Kept in the layout at zero opacity when inactive, so
                    // sorting a column doesn't shift the header text sideways.
                    .opacity(tab.sortKey == key ? 1 : 0)
                    .rotationEffect(.degrees(tab.sortAscending ? 0 : 180))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                               value: tab.sortAscending)
            }
            .foregroundStyle(theme.foreground.opacity(tab.sortKey == key ? 0.75 : 0.4))
        }
        .buttonStyle(.plain)
    }
}
