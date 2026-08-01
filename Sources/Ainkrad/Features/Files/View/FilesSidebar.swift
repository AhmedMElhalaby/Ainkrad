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
            VStack(alignment: .leading, spacing: 1) {
                ForEach(roots) { root in
                    SidebarRootRow(
                        root: root,
                        isSelected: root.url == currentDirectory,
                        onTap: { onSelect(root) }
                    )
                }
            }
            .padding(.horizontal, AinkradSpacing.sm)
            .padding(.vertical, AinkradSpacing.sm)
        }
        .frame(width: 164)
    }
}

/// Matches `FileRowView`'s density rather than `AinkradListRow`'s — a sidebar
/// whose rows are twice the height of the list they navigate reads as two
/// unrelated components bolted together.
private struct SidebarRootRow: View {
    let root: SidebarRoot
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradIconGlyph(systemName: root.icon, size: 12)
                .frame(width: 18)
            Text(root.name)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.foreground.opacity(isSelected ? 1 : 0.8))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, 5)
        .background(ChamferShape(cut: 4).fill(fill))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: hovering)
    }

    private var fill: Color {
        if isSelected { return theme.accentPrimary.opacity(0.22) }
        if hovering { return theme.foreground.opacity(0.06) }
        return .clear
    }
}
