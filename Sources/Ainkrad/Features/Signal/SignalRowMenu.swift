import AppKit
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The right-click menu on a feed row.
///
/// This is the shortest path from noticing noise to stopping it. Everything
/// here is reachable from Settings too, but a user who has just been
/// interrupted by the nineteenth identical warning is not in Settings — they
/// are looking at the row, and asking them to go elsewhere is asking them to
/// leave the problem behind in order to solve it.
@MainActor
enum SignalRowMenu {
    static func items(for event: SignalEvent,
                      rules: RoutingRules,
                      sourceName: String,
                      isRead: Bool,
                      onMuteKind: @escaping () -> Void,
                      onUnmuteKind: @escaping () -> Void,
                      onMuteSource: @escaping () -> Void,
                      onToggleRead: @escaping () -> Void,
                      onCopy: @escaping () -> Void) -> [AinkradMenuItem] {
        var items: [AinkradMenuItem] = []

        // Only one direction for now: `SignalStore` can set `read_at` but has
        // no way to clear it, and adding that is Phase 3's triage task. An item
        // that appears and does nothing would be worse than one that is absent,
        // so an already-read row simply does not offer it.
        if !isRead {
            items.append(AinkradMenuItem(title: "Mark as read",
                                         systemName: "envelope.open",
                                         action: onToggleRead))
        }
        items.append(AinkradMenuItem(title: "Copy", systemName: "doc.on.doc",
                                     action: onCopy))

        // Named, not generic. "Mute this" tells the user nothing about what
        // will go quiet; naming the source and the kind is the difference
        // between a control they trust and one they avoid.
        let isKindMuted = rules.sourceKindOverrides[
            SourceKind(source: event.source, kind: event.kind)] == [.feed]
        if isKindMuted {
            items.append(AinkradMenuItem(title: "Unmute \(sourceName) › \(event.kind)",
                                         systemName: "bell",
                                         action: onUnmuteKind))
        } else {
            items.append(AinkradMenuItem(title: "Mute \(sourceName) › \(event.kind)",
                                         systemName: "bell.slash",
                                         action: onMuteKind))
        }

        // Muting a whole source is a bigger step, so it is marked destructive
        // — not because it deletes anything, but because it is the item most
        // likely to be regretted, and the styling is the only warning a menu
        // can give.
        if !rules.mutedSources.contains(event.source) {
            items.append(AinkradMenuItem(title: "Mute everything from \(sourceName)",
                                         systemName: "bell.slash.fill",
                                         isDestructive: true,
                                         action: onMuteSource))
        }
        return items
    }

    /// Plain text, because the point is pasting a build error into a chat.
    static func clipboardText(for event: SignalEvent,
                              sourceName: String,
                              formatter: DateFormatter) -> String {
        var lines = ["[\(formatter.string(from: event.timestamp))] \(sourceName) · \(event.kind)",
                     event.title]
        if let body = event.body, !body.isEmpty { lines.append(body) }
        return lines.joined(separator: "\n")
    }
}
