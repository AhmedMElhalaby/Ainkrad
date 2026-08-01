import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// One file row.
///
/// Deliberately NOT built on `AinkradListRow`: that component is tuned for
/// settings lists (title + subtitle, generous padding), and a file manager's
/// core job is scanning hundreds of rows at a glance. This keeps the kit's
/// visual language — chamfer fill, leading accent bar, hover scan, theme tint,
/// resolved typography — at a density the list can actually use.
struct FileRowView: View {
    let entry: FileEntry
    /// Where the keyboard is. Drawn as a leading accent bar.
    let isCursor: Bool
    /// Whether the row is part of the selection. Drawn as a filled background.
    /// Separate from `isCursor` on purpose: you move the cursor to look and
    /// select to act, and the two must be tellable apart.
    let isSelected: Bool
    let now: Date
    let iconSize: CGFloat
    let rowPadding: CGFloat
    let showMetadata: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradIconGlyph(systemName: iconName(for: entry), size: iconSize)
                .opacity(entry.isSymlink ? 0.6 : 1)
                .frame(width: iconSize + 5)

            Text(entry.name)
                .font(AinkradFontResolver.font(.body, typography: typo))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: AinkradSpacing.md)

            if showMetadata {
                Text(formattedSize(entry.size, isDirectory: entry.isDirectory))
                    .frame(width: FilesColumnMetrics.sizeWidth, alignment: .trailing)
                Text(formattedDate(entry.modified, now: now))
                    .frame(width: FilesColumnMetrics.modifiedWidth, alignment: .trailing)
            }
        }
        .font(AinkradFontResolver.font(.caption, typography: typo))
        .foregroundStyle(theme.foreground.opacity(0.5))
        .monospacedDigit()
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, rowPadding)
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
        // Single tap fires IMMEDIATELY; the double-tap runs alongside it as a
        // simultaneous gesture. Declaring `.onTapGesture(count: 2)` ahead of a
        // single-tap handler makes SwiftUI wait out the double-click interval
        // before delivering the single tap — which is exactly why clicking
        // felt slow and unresponsive.
        .onTapGesture(perform: onTap)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap() })
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isCursor)
    }

    private var rowFill: Color {
        if isSelected { return theme.accentPrimary.opacity(0.22) }
        if hovering { return theme.foreground.opacity(0.06) }
        return .clear
    }
}
