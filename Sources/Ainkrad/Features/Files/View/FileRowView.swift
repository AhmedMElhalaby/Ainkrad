import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// One file row.
///
/// Deliberately NOT built on `AinkradListRow`: that component is tuned for
/// settings lists (title + subtitle, generous padding, ~58pt tall), and a file
/// manager's core job is scanning hundreds of rows at a glance — 23 visible
/// files in a full-height window undercuts the whole app. This keeps the kit's
/// visual language (chamfer fill, leading accent bar, hover scan, theme tint)
/// at roughly half the height.
struct FileRowView: View {
    let entry: FileEntry
    /// Where the keyboard is. Drawn as a leading accent bar + outline.
    let isCursor: Bool
    /// Whether the row is part of the selection. Drawn as a filled background.
    /// Separate from `isCursor` on purpose: you move the cursor to look and
    /// select to act, and the two must be tellable apart.
    let isSelected: Bool
    let now: Date
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradIconGlyph(systemName: iconName(for: entry), size: 13)
                .opacity(entry.isSymlink ? 0.6 : 1)
                .frame(width: 18)

            Text(entry.name)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: AinkradSpacing.md)

            Text(formattedSize(entry.size, isDirectory: entry.isDirectory))
                .frame(width: FilesColumnMetrics.sizeWidth, alignment: .trailing)
            Text(formattedDate(entry.modified, now: now))
                .frame(width: FilesColumnMetrics.modifiedWidth, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.foreground.opacity(0.5))
        .monospacedDigit()
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, 5)
        .background(ChamferShape(cut: 4).fill(rowFill))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.accentSecondary)
                .frame(width: isCursor ? 2 : 0)
        }
        // Hidden entries render dimmed when shown, so ⌘. reads as "reveal",
        // not "add more identical rows".
        .opacity(entry.isHidden ? 0.55 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onTapGesture(perform: onTap)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: hovering)
    }

    private var rowFill: Color {
        if isSelected { return theme.accentPrimary.opacity(0.22) }
        if hovering { return theme.foreground.opacity(0.06) }
        return .clear
    }
}
