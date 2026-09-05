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
        /// The source this row is ABOUT, carried so that clearing it never has
        /// to resolve a display name back to a source. It used to, and two
        /// consequences followed: two apps sharing a name cleared each other,
        /// and a source absent from the pane's list — which is filtered by
        /// `hasEverEmitted` — could not be cleared at all. That second one
        /// turned this panel, whose whole job is making a mute findable, into
        /// a Restore button that did nothing.
        let source: SignalSource
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
            out.append(Row(id: "source:\(source)", source: source,
                           sourceName: displayName(source), kind: nil, mode: .off))
        }
        for (source, channels) in rules.sourceOverrides
            where channels == [.feed] && !rules.mutedSources.contains(source) {
            out.append(Row(id: "source:\(source)", source: source,
                           sourceName: displayName(source), kind: nil, mode: .feedOnly))
        }
        for (key, channels) in rules.sourceKindOverrides where channels == [.feed] {
            out.append(Row(id: "kind:\(key.source):\(key.kind)",
                           source: key.source,
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

    /// Removes whatever a row describes, restoring the default.
    ///
    /// Pure and keyed on `row.source`, so it works for a source the settings
    /// list has never shown — a source muted from a feed row's context menu
    /// before it ever emitted is exactly the case the user cannot fix anywhere
    /// else.
    static func clear(_ row: Row, from rules: inout RoutingRules) {
        if let kind = row.kind {
            rules.sourceKindOverrides[SourceKind(source: row.source, kind: kind)] = nil
        } else {
            rules.mutedSources.remove(row.source)
            rules.sourceOverrides[row.source] = nil
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
