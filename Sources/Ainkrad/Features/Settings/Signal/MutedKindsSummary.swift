import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Every non-default notification override, in one list, each removable.
///
/// This panel exists because a mute the user cannot find is a bug they will
/// report as "notifications stopped working". Per-kind mutes are set from a
/// row's context menu, days or weeks before the day the user wonders why an app
/// has gone quiet — so there has to be one place that answers it.
struct MutedKindsSummary: View {
    struct Row: Identifiable, Equatable {
        let id: String
        let sourceName: String
        /// Nil for a whole-source setting.
        let kind: String?
        let mode: SignalDeliveryMode
    }

    let rows: [Row]
    var onClear: (Row) -> Void = { _ in }
    var onClearAll: () -> Void = {}

    @Environment(\.ainkradTheme) private var theme

    /// Built here rather than in the view so the ordering and the labelling are
    /// testable without rendering.
    static func rows(from rules: RoutingRules,
                     displayName: (SignalSource) -> String) -> [Row] {
        var out: [Row] = []
        for source in rules.mutedSources.sorted(by: { displayName($0) < displayName($1) }) {
            out.append(Row(id: "source:\(source)", sourceName: displayName(source),
                           kind: nil, mode: .off))
        }
        for (source, channels) in rules.sourceOverrides
            where channels == [.feed] && !rules.mutedSources.contains(source) {
            out.append(Row(id: "source:\(source)", sourceName: displayName(source),
                           kind: nil, mode: .feedOnly))
        }
        for (key, channels) in rules.sourceKindOverrides where channels == [.feed] {
            out.append(Row(id: "kind:\(key.source):\(key.kind)",
                           sourceName: displayName(key.source),
                           kind: key.kind, mode: .feedOnly))
        }
        // Whole-source settings first, then kinds, each alphabetical — a stable
        // order, so the list does not reshuffle as the user removes entries.
        return out.sorted {
            ($0.kind == nil ? 0 : 1, $0.sourceName, $0.kind ?? "")
                < ($1.kind == nil ? 0 : 1, $1.sourceName, $1.kind ?? "")
        }
    }

    var body: some View {
        AinkradSettingsPanel(
            title: "Muted",
            hint: "Everything you have turned down, in one place. Removing an entry "
                + "restores the default immediately."
        ) {
            if rows.isEmpty {
                // Shown, not hidden. The user needs to be able to CHECK that
                // nothing is muted; an absent panel cannot answer that.
                AinkradCaption("Nothing is muted.")
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(rows) { row in entry(row) }
                    HStack {
                        Spacer()
                        AinkradButton(title: "Turn everything back on", style: .ghost,
                                      action: onClearAll)
                    }
                }
            }
        }
    }

    private func entry(_ row: Row) -> some View {
        HStack(spacing: AinkradSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.sourceName)
                    .font(AinkradFont.display(11.5, weight: .medium))
                    .foregroundStyle(theme.foreground)
                if let kind = row.kind {
                    Text(kind)
                        .font(AinkradFont.mono(9.5))
                        .foregroundStyle(theme.foreground.opacity(0.5))
                }
            }
            Spacer(minLength: AinkradSpacing.sm)
            AinkradBadge(text: row.mode.label, tint: theme.accentSecondary)
            AinkradButton(title: "Restore", style: .ghost) { onClear(row) }
        }
    }
}
