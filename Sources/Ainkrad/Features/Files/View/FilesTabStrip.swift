import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// Per-pane tabs. Hidden entirely when there is only one — a lone tab is
/// chrome that earns nothing.
struct FilesTabStrip: View {
    let store: FilesPaneStore

    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        if store.tabs.count > 1 {
            HStack(spacing: AinkradSpacing.xs) {
                ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                    HStack(spacing: AinkradSpacing.xs) {
                        Text(tab.title).font(.caption)
                        Button {
                            store.closeTab(at: index)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, AinkradSpacing.sm)
                    .padding(.vertical, AinkradSpacing.xs)
                    .background(
                        ChamferShape(cut: 6).fill(
                            index == store.activeTabIndex
                                ? theme.accentPrimary.opacity(0.18)
                                : Color.clear
                        )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { store.selectTab(at: index) }
                }
                Spacer()
            }
            .padding(.horizontal, FilesColumnMetrics.headerInset)
            .padding(.top, AinkradSpacing.sm)
        }
    }
}
