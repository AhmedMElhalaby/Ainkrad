import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// One file row. A thin renderer over `FileEntry` — all behaviour (selection
/// semantics, navigation) belongs to the list and the tab, not here.
struct FileRowView: View {
    let entry: FileEntry
    let isSelected: Bool
    let now: Date
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        AinkradListRow(
            isSelected: isSelected,
            onTap: onTap,
            leading: {
                AinkradIconGlyph(systemName: iconName(for: entry), size: 16)
                    // Symlinks read as aliases, dimmed to distinguish them
                    // from their targets without adding a second glyph.
                    .opacity(entry.isSymlink ? 0.6 : 1)
            },
            title: entry.name,
            trailing: {
                HStack(spacing: AinkradSpacing.lg) {
                    Text(formattedSize(entry.size, isDirectory: entry.isDirectory))
                        .frame(width: 80, alignment: .trailing)
                    Text(formattedDate(entry.modified, now: now))
                        .frame(width: 140, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(theme.foreground.opacity(0.55))
                .monospacedDigit()
            }
        )
        // Hidden entries render dimmed when shown, so ⌘. reads as "reveal",
        // not "add more identical rows".
        .opacity(entry.isHidden ? 0.5 : 1)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap() })
    }
}
