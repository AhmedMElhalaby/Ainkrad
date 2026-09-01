import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The in-window feed: the full surface, with search, filters and bulk read.
///
/// Reads its rows through the closures rather than owning a store, so the same
/// view renders live host state and a seeded snapshot without a second code
/// path.
struct SignalFeedIsland: View {
    let events: [SignalEvent]
    var unread: Int = 0
    var repeatCounts: [UUID: Int] = [:]
    var readIDs: Set<UUID> = []
    var knownSources: [SignalSource] = []
    var isDegraded: Bool = false
    var now: Date = Date()
    var onSearch: (String) -> Void = { _ in }
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }
    var onMarkAllRead: () -> Void = {}

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @State private var query = ""
    @State private var activeSeverities: Set<SignalSeverity> = []
    @State private var activeSource: SignalSource?

    private var filtered: [SignalEvent] {
        events.filter { event in
            (activeSeverities.isEmpty || activeSeverities.contains(event.severity))
                && (activeSource == nil || event.source == activeSource)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            filterBar
            if isDegraded { degradedNotice }
            if filtered.isEmpty && !events.isEmpty {
                noMatches
            } else {
                SignalFeedList(events: filtered,
                               repeatCounts: repeatCounts,
                               readIDs: readIDs,
                               now: now,
                               onActivate: onActivate,
                               onAction: onAction)
            }
        }
        // No background of its own: the hosting `AinkradPanel` supplies the
        // blur and tint, and an opaque fill here would cover its glass.
    }

    private var header: some View {
        HStack(spacing: AinkradSpacing.sm + 2) {
            Text("Notifications")
                .font(AinkradFont.display(15, weight: .semibold))
                .foregroundStyle(theme.foreground)
            if unread > 0 {
                AinkradBadge(text: "\(unread) new", tint: theme.accentSecondary)
            }
            Spacer()
            AinkradSearchField(text: $query, placeholder: "Search") { onSearch(query) }
                .frame(width: 190)
            if unread > 0 {
                Button(action: onMarkAllRead) {
                    Text("Mark all read")
                        .font(AinkradFont.display(10.5, weight: .medium))
                        .foregroundStyle(theme.accentPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AinkradSpacing.lg)
        .padding(.top, AinkradSpacing.lg - 2)
        .padding(.bottom, AinkradSpacing.sm + 2)
    }

    private var filterBar: some View {
        // `AinkradSwatchChip` is the kit's toggle chip: chamfered, hover-lit,
        // and it carries a colour dot — which is exactly what a severity filter
        // wants, so the severity ramp is legible without reading the label.
        HStack(spacing: AinkradSpacing.xs + 2) {
            ForEach(SignalSeverity.allCases, id: \.self) { severity in
                AinkradSwatchChip(
                    label: severity.rawValue.capitalized,
                    swatch: SignalRowFormatter.status(for: severity)
                        .color(in: theme, statusColors: status),
                    isOn: activeSeverities.contains(severity)) {
                    if activeSeverities.contains(severity) { activeSeverities.remove(severity) }
                    else { activeSeverities.insert(severity) }
                }
            }
            ForEach(Array(knownSources.enumerated()), id: \.offset) { _, source in
                AinkradSwatchChip(
                    label: SignalRowFormatter.sourceLabel(source),
                    swatch: theme.accentSecondary,
                    isOn: activeSource == source) {
                    activeSource = (activeSource == source) ? nil : source
                }
            }
            Spacer()
        }
        .padding(.horizontal, AinkradSpacing.lg)
        .padding(.bottom, AinkradSpacing.sm)
    }

    /// The feed still works with no store - it just cannot remember. Saying so
    /// is better than a mysteriously short history.
    private var degradedNotice: some View {
        HStack(spacing: AinkradSpacing.sm - 1) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10.5))
                .foregroundStyle(status.warning)
            Text("History unavailable — events are kept in memory for this session only.")
                .font(AinkradFont.display(10.5))
                .foregroundStyle(theme.foreground.opacity(0.62))
        }
        .padding(.horizontal, AinkradSpacing.lg)
        .padding(.vertical, AinkradSpacing.sm - 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceElevated.opacity(0.6))
    }

    private var noMatches: some View {
        VStack(spacing: AinkradSpacing.sm) {
            Text("No matching events")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.55))
            AinkradButton(title: "Clear filters", style: .ghost) {
                activeSeverities.removeAll(); activeSource = nil
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AinkradSpacing.xl + AinkradSpacing.lg)
    }
}
