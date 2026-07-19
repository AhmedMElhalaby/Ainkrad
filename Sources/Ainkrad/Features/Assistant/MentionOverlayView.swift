import SwiftUI
import AinkradAppKit

/// `@`-triggered file-mention overlay: a fuzzy `FileMatch` list from
/// `WorkspaceFileIndex.search(query:limit:)`, presented via
/// `.ainkradFloatingPanel` anchored to the composer. Selecting a row inserts a
/// `@path` reference into the draft (see `AssistantComposerBar.insertMention`).
/// Presentation-only, mirroring `CommandPaletteView` — keyboard navigation is
/// driven by the composer's shared key monitor.
struct MentionOverlayView: View {
    let matches: [FileMatch]
    @Binding var selectedIndex: Int
    let tokens: DesignTokens
    let onSelect: (FileMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if matches.isEmpty {
                Text("No matching files")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                    .padding(10)
            } else {
                ForEach(Array(matches.enumerated()), id: \.element.path) { index, match in
                    AinkradListRow(
                        isSelected: index == selectedIndex,
                        onTap: { onSelect(match) },
                        leading: {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tokens.accentSecondary)
                        },
                        title: match.name,
                        subtitle: match.path,
                        trailing: { EmptyView() }
                    )
                }
            }
        }
        .padding(6)
        .frame(minWidth: 300)
    }
}
