import SwiftUI
import AinkradAppKit
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
        .background(theme.surface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Feed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.foreground)
            if unread > 0 {
                Text("\(unread) new")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(theme.accentPrimary))
            }
            Spacer()
            searchField
            if unread > 0 {
                Button("Mark all read", action: onMarkAllRead)
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.accentPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.4))
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.foreground)
                .frame(width: 130)
                .onSubmit { onSearch(query) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(theme.surfaceElevated))
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(SignalSeverity.allCases, id: \.self) { severity in
                chip(label: severity.rawValue.capitalized,
                     tint: SignalRowFormatter.color(for: severity, in: status),
                     isOn: activeSeverities.contains(severity)) {
                    if activeSeverities.contains(severity) { activeSeverities.remove(severity) }
                    else { activeSeverities.insert(severity) }
                }
            }
            if !knownSources.isEmpty {
                ForEach(Array(knownSources.enumerated()), id: \.offset) { _, source in
                    chip(label: SignalRowFormatter.sourceLabel(source),
                         tint: theme.accentSecondary,
                         isOn: activeSource == source) {
                        activeSource = (activeSource == source) ? nil : source
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func chip(label: String, tint: Color, isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isOn ? theme.background : theme.foreground.opacity(0.62))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(isOn ? tint : theme.surfaceElevated))
        }
        .buttonStyle(.plain)
    }

    /// The feed still works with no store - it just cannot remember. Saying so
    /// is better than a mysteriously short history.
    private var degradedNotice: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10.5))
                .foregroundStyle(status.warning)
            Text("History unavailable — events are kept in memory for this session only.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.foreground.opacity(0.62))
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceElevated.opacity(0.6))
    }

    private var noMatches: some View {
        VStack(spacing: 5) {
            Text("No matching events")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.55))
            Button("Clear filters") {
                activeSeverities.removeAll(); activeSource = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(theme.accentPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
