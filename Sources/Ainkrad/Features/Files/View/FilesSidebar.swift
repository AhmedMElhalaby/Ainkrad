import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The roots list. Selection follows the active tab's directory rather than
/// holding its own state — otherwise navigating by any other means would
/// leave the sidebar highlighting the wrong row.
struct FilesSidebar: View {
    let roots: [SidebarRoot]
    let currentDirectory: URL
    let onSelect: (SidebarRoot) -> Void

    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(roots) { root in
                    AinkradListRow(
                        isSelected: root.url == currentDirectory,
                        onTap: { onSelect(root) },
                        leading: { AinkradIconGlyph(systemName: root.icon, size: 14) },
                        title: root.name,
                        trailing: { EmptyView() }
                    )
                }
            }
            .padding(.horizontal, AinkradSpacing.sm)
            .padding(.vertical, AinkradSpacing.md)
        }
        .frame(width: 180)
    }
}
