import Foundation
import Observation
import AinkradSignal

/// Receives the routing decision and does something about it. Split out so
/// `SignalCenter` is testable without AppKit, notification authorization, or
/// a window.
@MainActor protocol SignalDeliverer: AnyObject {
    func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>)
}

/// Supplies the user's current situation. The host implementation reads
/// frontmost state, visible apps and Do Not Disturb.
@MainActor protocol SignalContextProviding {
    var deliveryContext: DeliveryContext { get }
}

/// The single live owner of the feed. Sole writer to `SignalStore`.
@MainActor
@Observable
final class SignalCenter {
    /// How many events the degraded (no-store) path keeps in memory.
    static let degradedBufferLimit = 200
    /// A full retention sweep runs at launch and then at most once per this
    /// many inserts - enforcing on every insert would put two DELETEs with
    /// subqueries in the path of every event.
    static let retentionSweepInterval = 100

    private let store: SignalStore?
    private let ingest: SignalIngest?
    private weak var deliverer: (any SignalDeliverer)?
    private let contextProvider: any SignalContextProviding

    private var degradedBuffer: [SignalEvent] = []
    private var insertsSinceSweep = 0

    /// Newest-first window over the feed, kept live for the UI.
    private(set) var recent: [SignalEvent] = []
    private(set) var unreadCounts: [SignalSource: Int] = [:]
    var totalUnread: Int { unreadCounts.values.reduce(0, +) }
    /// True when the store could not be opened; the feed is memory-only.
    let isDegraded: Bool

    var rules: RoutingRules {
        didSet { onRulesChanged?(rules) }
    }
    var retention: RetentionPolicy {
        didSet { onRetentionChanged?(retention) }
    }
    /// Set by the bootstrap so changes persist; nil in tests.
    var onRulesChanged: ((RoutingRules) -> Void)?
    var onRetentionChanged: ((RetentionPolicy) -> Void)?

    init(store: SignalStore?,
         deliverer: (any SignalDeliverer)?,
         contextProvider: any SignalContextProviding,
         rules: RoutingRules = .default,
         retention: RetentionPolicy = .default) {
        self.store = store
        self.ingest = store.map { SignalIngest(store: $0) }
        self.deliverer = deliverer
        self.contextProvider = contextProvider
        self.rules = rules
        self.retention = retention
        self.isDegraded = (store == nil)
        if let store {
            store.enforceRetention(retention)
            self.recent = store.page(filter: .all, before: nil, limit: 200)
            self.unreadCounts = store.unreadCounts()
        }
    }

    /// Record an event and deliver it. Never throws, never fails the caller -
    /// the doctrine inherited from `UserNotificationRunNotifier`: a run's
    /// success is never gated on a notification.
    func emit(_ draft: SignalDraft, from source: SignalSource) {
        let event: SignalEvent
        if let ingest {
            switch ingest.accept(draft, from: source) {
            case .accepted(let stored):
                event = stored
                insertsSinceSweep += 1
                if insertsSinceSweep >= Self.retentionSweepInterval {
                    insertsSinceSweep = 0
                    store?.enforceRetention(retention)
                }
            case .coalesced(let stored):
                event = stored
            case .rejected:
                // Swallowed by design. A malformed event is a bug in the
                // emitter, not a failure of the emitter's work.
                return
            }
            refreshFromStore()
        } else {
            guard SignalKind.isValid(draft.kind),
                  !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            event = SignalEvent(source: source, kind: draft.kind, severity: draft.severity,
                                title: draft.title, body: draft.body,
                                proposedImportance: draft.importance,
                                deepLink: draft.deepLink, actions: draft.actions,
                                dedupeKey: draft.dedupeKey).normalized(source: source)
            degradedBuffer.insert(event, at: 0)
            if degradedBuffer.count > Self.degradedBufferLimit { degradedBuffer.removeLast() }
            recent = degradedBuffer
            unreadCounts[source, default: 0] += 1
        }

        let channels = route(event, rules: rules, context: contextProvider.deliveryContext)
        deliverer?.deliver(event, to: channels)
    }

    func page(filter: SignalFilter, before: Date?, limit: Int) -> [SignalEvent] {
        store?.page(filter: filter, before: before, limit: limit) ?? degradedBuffer
    }

    func search(_ query: String, filter: SignalFilter = .all, limit: Int = 50) -> [SignalEvent] {
        guard let store else {
            let needle = query.lowercased()
            return degradedBuffer.filter {
                $0.title.lowercased().contains(needle) || ($0.body?.lowercased().contains(needle) ?? false)
            }
        }
        return store.search(query, filter: filter, limit: limit)
    }

    func markRead(ids: [UUID]) {
        store?.markRead(ids: ids)
        refreshFromStore()
    }

    func markAllRead(filter: SignalFilter) {
        guard let store else { unreadCounts = [:]; return }
        store.markAllRead(filter: filter)
        refreshFromStore()
    }

    func setPinned(_ pinned: Bool, id: UUID) {
        store?.setPinned(pinned, id: id)
        refreshFromStore()
    }

    /// Total rows currently held, for the Settings history panel.
    var eventCount: Int { store?.page(filter: .all, before: nil, limit: Int.max).count ?? degradedBuffer.count }

    /// Empties the feed, keeping pinned rows - the same exemption retention
    /// uses, so "clear" never destroys something the user deliberately kept.
    func clearFeed() {
        store?.enforceRetention(RetentionPolicy(maxAgeDays: 0, maxEvents: 0))
        degradedBuffer.removeAll()
        refreshFromStore()
        if store == nil { recent = []; unreadCounts = [:] }
    }

    func unreadCount(for source: SignalSource) -> Int { unreadCounts[source] ?? 0 }

    private func refreshFromStore() {
        guard let store else { return }
        recent = store.page(filter: .all, before: nil, limit: 200)
        unreadCounts = store.unreadCounts()
    }
}
