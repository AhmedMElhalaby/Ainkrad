import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The sortable header + scrolling rows for one tab.
struct FileListView: View {
    @Bindable var tab: FilesTab

    @Environment(\.ainkradTheme) private var theme

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
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(tab.visibleEntries) { entry in
                        FileRowView(
                            entry: entry,
                            isSelected: tab.selection.contains(entry.url),
                            now: now,
                            onTap: { tab.selection = [entry.url] },
                            onDoubleTap: { tab.descend(into: entry) }
                        )
                    }
                }
                .padding(.horizontal, AinkradSpacing.sm)
                .padding(.vertical, AinkradSpacing.xs)
            }
        }
    }

    /// Click-to-sort column titles. No divider under the header — the design
    /// language forbids separator lines; separation reads via spacing.
    private var header: some View {
        HStack(spacing: AinkradSpacing.lg) {
            headerButton("Name", key: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerButton("Size", key: .size).frame(width: 80, alignment: .trailing)
            headerButton("Modified", key: .modified).frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, AinkradSpacing.md)
        .padding(.vertical, AinkradSpacing.sm)
    }

    private func headerButton(_ title: String, key: FileSortKey) -> some View {
        Button {
            // Mirrors `nextSort(current:column:)` from the kit: a new column
            // starts ascending, the active column toggles direction.
            if tab.sortKey == key {
                tab.sortAscending.toggle()
            } else {
                tab.sortKey = key
                tab.sortAscending = true
            }
        } label: {
            HStack(spacing: AinkradSpacing.xs) {
                Text(title.uppercased())
                    .font(.caption2)
                    .tracking(0.8)
                if tab.sortKey == key {
                    Image(systemName: tab.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .foregroundStyle(theme.foreground.opacity(tab.sortKey == key ? 0.9 : 0.5))
        }
        .buttonStyle(.plain)
    }
}
