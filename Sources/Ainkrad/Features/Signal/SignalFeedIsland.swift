import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The in-window feed: a source rail, severity filters, search, and the list.
///
/// Reads its rows through closures rather than owning a store, so the same view
/// renders live host state and a seeded snapshot without a second code path.
struct SignalFeedIsland: View {
    let events: [SignalEvent]
    var unread: Int = 0
    var repeatCounts: [UUID: Int] = [:]
    var readIDs: Set<UUID> = []
    var isDegraded: Bool = false
    var now: Date = Date()
    /// Persisted, so the filter the user built survives closing the overlay.
    @Binding var viewState: SignalViewState
    var searchText: Binding<String>
    /// Nil when not searching; a count when searching, even if it is zero.
    var searchResultCount: Int?
    var displayName: (SignalSource) -> String = { SignalPresentation.sourceLabel($0) }
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }
    var onMarkAllRead: () -> Void = {}
    var onConfigureSource: (SignalSource) -> Void = { _ in }
    var menuItems: (SignalEvent) -> [AinkradMenuItem] = { _ in [] }

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    /// Severity, source and unread are applied here rather than by re-querying:
    /// the caller may have handed us search results, and re-filtering in the
    /// store would discard them.
    private var filtered: [SignalEvent] {
        events.filter { event in
            (viewState.severities.isEmpty || viewState.severities.contains(event.severity))
                && (viewState.selectedSource == nil || event.source == viewState.selectedSource)
                && (!viewState.unreadOnly || !readIDs.contains(event.id))
        }
    }

    private var railItems: [SignalSourceRailItem] {
        SignalSourceRailItem.build(events: events, readIDs: readIDs, name: displayName)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SignalSourceRail(items: railItems,
                             selection: $viewState.selectedSource,
                             onConfigure: onConfigureSource)
            VStack(alignment: .leading, spacing: 0) {
                header
                filterBar
                if isDegraded { degradedNotice }
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty && !events.isEmpty {
            noMatches
        } else if viewState.grouping == .bySource {
            SignalFeedGroupedList(
                groups: SignalPresentation.sourceGroups(filtered, readIDs: readIDs,
                                                        name: displayName),
                collapsed: $viewState.collapsedSources,
                repeatCounts: repeatCounts, readIDs: readIDs, now: now,
                onActivate: onActivate, onAction: onAction, menuItems: menuItems)
        } else {
            SignalFeedList(events: filtered, repeatCounts: repeatCounts, readIDs: readIDs,
                           now: now, calendar: .current, onActivate: onActivate,
                           onAction: onAction, menuItems: menuItems)
        }
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
            AinkradSearchField(text: searchText, placeholder: "Search")
                .frame(width: 190)
            if unread > 0 {
                Button(action: onMarkAllRead) {
                    // Names what it will actually do. Under a filter, "Mark all
                    // read" reads as everything and quietly means twelve — so
                    // the user clears rows they cannot see.
                    Text(viewState.isShowingEverything
                         ? "Mark all read"
                         : "Mark \(filtered.filter { !readIDs.contains($0.id) }.count) read")
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
        HStack(spacing: AinkradSpacing.xs + 2) {
            ForEach(SignalSeverity.allCases, id: \.self) { severity in
                AinkradSwatchChip(
                    label: severity.rawValue.capitalized,
                    swatch: SignalPresentation.status(for: severity)
                        .color(in: theme, statusColors: status),
                    isOn: viewState.severities.contains(severity)) {
                    if viewState.severities.contains(severity) {
                        viewState.severities.remove(severity)
                    } else {
                        viewState.severities.insert(severity)
                    }
                }
            }
            AinkradSwatchChip(label: "Unread", swatch: theme.accentSecondary,
                              isOn: viewState.unreadOnly) {
                viewState.unreadOnly.toggle()
            }
            Spacer()
            if let count = searchResultCount {
                // A search that silently replaces the list is the reason the
                // empty state used to be a dead end: the user could not tell
                // whether a filter or a query had emptied it.
                Text(count == 1 ? "1 result" : "\(count) results")
                    .font(AinkradFont.mono(9.5))
                    .foregroundStyle(theme.foreground.opacity(0.5))
            }
            AinkradSegmentedPicker(
                items: [SignalViewState.Grouping.byTime, .bySource],
                selection: $viewState.grouping,
                label: { $0 == .byTime ? "Time" : "App" })
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
            // Clears the SEARCH as well as the filters. The old button cleared
            // only the chips, so a user who had searched stayed stuck in an
            // empty feed with a button that appeared not to work.
            AinkradButton(title: "Clear all", style: .ghost) {
                viewState.severities.removeAll()
                viewState.selectedSource = nil
                viewState.unreadOnly = false
                searchText.wrappedValue = ""
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AinkradSpacing.xl + AinkradSpacing.lg)
    }
}
