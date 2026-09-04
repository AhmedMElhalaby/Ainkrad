import Foundation
import Observation
import AinkradHostRuntime
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
    /// Kept alive by whoever built the center when the dispatcher has no other
    /// owner. `deliverer` is weak so a torn-down host does not leak, which
    /// means an unretained dispatcher turns every delivery into a silent no-op
    /// - a failure mode no routing test can see.
    private var retainedDeliverer: (any SignalDeliverer)?
    var deliveryTargetIsAliveForTesting: Bool { deliverer != nil }
    private let contextProvider: any SignalContextProviding

    private var degradedBuffer: [SignalEvent] = []
    private var insertsSinceSweep = 0

    /// Newest-first window over the feed, kept live for the UI.
    private(set) var recent: [SignalEvent] = []
    /// Per-row read state and coalesce counts for `recent`. Kept beside the
    /// events rather than on them: `SignalEvent` is the plugin-facing envelope.
    private(set) var rowStates: [UUID: SignalStore.SignalRowState] = [:]
    /// Ids in `recent` the user has already seen.
    var readIDs: Set<UUID> { Set(rowStates.filter { $0.value.isRead }.map(\.key)) }
    /// Rows the user has kept. Exempt from retention and from clearing, which
    /// the store has honoured since M1 — this is the first time anything can
    /// display which rows those are.
    var pinnedIDs: Set<UUID> { Set(rowStates.filter { $0.value.isPinned }.map(\.key)) }
    /// Coalesce counts, for the `xN` badge.
    var repeatCounts: [UUID: Int] { rowStates.mapValues(\.repeatCount) }
    private(set) var unreadCounts: [SignalSource: Int] = [:] {
        didSet { onUnreadChanged?(totalUnread) }
    }
    /// Fired whenever the unread total moves, so the menu-bar badge does not
    /// have to poll or set up its own observation.
    var onUnreadChanged: ((Int) -> Void)?
    /// Fired once per recorded event, AFTER this center's own delivery.
    ///
    /// The order is the point: cross-app subscribers must never see an event
    /// before the user's own surfaces do. Fired for coalesced events too — a
    /// repeat is still a thing that happened, and a subscriber that only heard
    /// about the first of five identical failures would be misinformed rather
    /// than merely under-informed.
    var onEventRecorded: ((SignalEvent) -> Void)?
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
            self.rowStates = store.rowStates(limit: 200)
            self.unreadCounts = store.unreadCounts()
        }
    }

    /// Record an event and deliver it. Never throws, never fails the caller -
    /// the doctrine inherited from the old run notifier: a run's
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
        // Last, deliberately: see `onEventRecorded`.
        onEventRecorded?(event)
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
        onRead?(ids)
    }

    func markAllRead(filter: SignalFilter) {
        guard let store else { unreadCounts = [:]; return }
        store.markAllRead(filter: filter)
        refreshFromStore()
    }

    /// Puts a row back on the pile. The counterpart `markRead` never had —
    /// without it, a row read by accident is unrecoverable and the unread
    /// count is a number the user can only push down.
    func markUnread(ids: [UUID]) {
        store?.markUnread(ids: ids)
        refreshFromStore()
    }

    /// Removes rows for good, index included. Distinct from marking read: the
    /// user is saying they are done with it, not that they have seen it.
    func dismiss(ids: [UUID]) {
        store?.delete(ids: ids)
        degradedBuffer.removeAll { ids.contains($0.id) }
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

    /// Sources that have actually recorded something, host and Sage aside.
    ///
    /// Settings lists a delivery control per source, and a control for an app
    /// that has never said anything is a dead row — the same reasoning the
    /// feed's source chips already use. Memoized because it is read during view
    /// updates and each miss is a query; invalidated whenever the store changes.
    private var emittingSourceCache: Set<SignalSource>?

    /// What a source has been emitting, for its per-kind control rows. Empty
    /// with no store: a degraded session has no history to describe.
    func kindActivity(for source: SignalSource) -> [SignalKindActivity] {
        store?.kindActivity(for: source, since: nil) ?? []
    }

    func hasEverEmitted(_ source: SignalSource) -> Bool {
        if let cache = emittingSourceCache { return cache.contains(source) }
        guard let store else {
            let live = Set(degradedBuffer.map(\.source))
            emittingSourceCache = live
            return live.contains(source)
        }
        // One page, not one query per source: the caller is enumerating every
        // installed app, so N queries would be N round trips per view update.
        let recentEnough = store.page(filter: .all, before: nil, limit: 5000)
        let live = Set(recentEnough.map(\.source))
        emittingSourceCache = live
        return live.contains(source)
    }

    /// Resolves an event by id, for a surface that has only the id — a clicked
    /// macOS banner carries `signalEventID` in its `userInfo` and nothing else.
    ///
    /// `recent` first: it is in memory and is the overwhelmingly common case,
    /// since a banner is usually clicked within seconds. Falls through to the
    /// store for anything older than the in-memory window, and to the degraded
    /// buffer when there is no store at all. `nil` means genuinely gone —
    /// evicted by retention, or the feed was cleared.
    func event(id: UUID) -> SignalEvent? {
        recent.first { $0.id == id }
            ?? store?.event(id: id)
            ?? degradedBuffer.first { $0.id == id }    }

    func unreadCount(for source: SignalSource) -> Int { unreadCounts[source] ?? 0 }

    /// Set by the bootstrap: runs an action the user chose from a BANNER.
    ///
    /// The feed routes its own actions through `SignalActionRouter`, which is a
    /// view-layer type holding the emitter hub. A banner has no view to route
    /// through, so it needs this seam — the same shape `onActivateDeepLink`
    /// already uses for the same reason.
    var onInvokeAction: ((SignalEvent, SignalAction) -> Void)?

    /// Set by the bootstrap: called with events that have just been read, so a
    /// banner already sitting in Notification Center can be withdrawn. Reading
    /// a row in-app should not leave an unread-looking banner behind.
    var onRead: (([UUID]) -> Void)?

    func invokeBannerAction(_ action: SignalAction, on event: SignalEvent) {
        onInvokeAction?(event, action)
    }

    /// Set by the bootstrap: opens the deep link's target app with its payload.
    var onActivateDeepLink: ((SignalDeepLink) -> Void)?

    /// The user tapped a row. Marks it read and follows its deep link, if it
    /// has one.
    ///
    /// One method rather than a closure per surface: the dropdown and the
    /// overlay must behave identically, and two call sites drift.
    func activate(_ event: SignalEvent) {
        markRead(ids: [event.id])
        guard let deepLink = event.deepLink else { return }
        onActivateDeepLink?(deepLink)
    }

    /// Takes ownership of the dispatcher. Used by the bootstrap factory, where
    /// the dispatcher exists only to serve this center.
    func retainDeliverer(_ deliverer: any SignalDeliverer) {
        retainedDeliverer = deliverer
    }

    private func refreshFromStore() {
        emittingSourceCache = nil
        guard let store else { return }
        recent = store.page(filter: .all, before: nil, limit: 200)
        rowStates = store.rowStates(limit: 200)
        unreadCounts = store.unreadCounts()
    }
}

/// Lets `SignalEmitterHub` (in `AinkradHostRuntime`, which cannot see this
/// type) drive the feed. The hub holds this weakly, so a torn-down host does
/// not keep the feed alive.
extension SignalCenter: SignalEmitting {
    func record(_ appID: String, kind: String, severity: SignalSeverity, title: String,
                body: String?, importance: SignalImportance,
                deepLink: SignalDeepLink?, actions: [SignalAction], dedupeKey: String?) {
        emit(SignalDraft(kind: kind, severity: severity, title: title, body: body,
                         importance: importance, deepLink: deepLink,
                         actions: actions, dedupeKey: dedupeKey),
             from: .app(appID: appID))
    }

    func events(forAppID appID: String, limit: Int) -> [SignalEvent] {
        var filter = SignalFilter.all
        filter.sources = [.app(appID: appID)]
        return page(filter: filter, before: nil, limit: limit)
    }
}
