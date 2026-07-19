import SwiftUI
import AinkradAppKit

/// `/`-triggered slash-command palette: a fuzzy-filtered list over
/// `CommandRegistry.all()`, presented via `.ainkradFloatingPanel` anchored to
/// the composer (see `AssistantComposerBar`). Keyboard navigation (Up/Down to
/// move `selectedIndex`, Return to confirm) is driven by the composer's own
/// key monitor — this view is presentation-only, reading `selectedIndex` as a
/// binding so both stay in sync.
struct CommandPaletteView: View {
    let commands: [SlashCommand]
    let query: String
    @Binding var selectedIndex: Int
    let tokens: DesignTokens
    let onSelect: (SlashCommand) -> Void

    private var filtered: [SlashCommand] {
        CommandPaletteView.filter(commands, query: query)
    }

    var body: some View {
        let rows = filtered
        VStack(alignment: .leading, spacing: 4) {
            if rows.isEmpty {
                Text("No matching commands")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                    .padding(10)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.name) { index, command in
                    AinkradListRow(
                        isSelected: index == selectedIndex,
                        onTap: { onSelect(command) },
                        leading: {
                            Image(systemName: "chevron.right.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tokens.accentSecondary)
                        },
                        title: "/\(command.name)",
                        subtitle: command.usage,
                        trailing: { EmptyView() }
                    )
                }
            }
        }
        .padding(6)
        .frame(minWidth: 260)
    }

    /// Substring match over the command name and summary — the same
    /// permissive filter used regardless of case. Pure — unit-testable
    /// without SwiftUI.
    static func filter(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return commands }
        return commands.filter { $0.name.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
    }
}
