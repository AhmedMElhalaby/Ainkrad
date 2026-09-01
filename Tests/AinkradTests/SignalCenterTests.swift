import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("SignalCenter")
final class SignalCenterTests {
    private final class SpyDeliverer: SignalDeliverer {
        var delivered: [(SignalEvent, Set<DeliveryChannel>)] = []
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
            delivered.append((event, channels))
        }
    }

    private struct StubContext: SignalContextProviding {
        var deliveryContext: DeliveryContext
    }

    private let url: URL
    private let store: SignalStore
    private let deliverer = SpyDeliverer()
    private let center: SignalCenter

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        store = try SignalStore(url: url)
        center = SignalCenter(
            store: store,
            deliverer: deliverer,
            contextProvider: StubContext(deliveryContext: DeliveryContext(
                hostIsFrontmost: false, visibleAppIDs: [],
                systemDoNotDisturb: false, hostFocusMode: false)))
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    private func draft(_ kind: String = "install.completed",
                       _ severity: SignalSeverity = .success) -> SignalDraft {
        SignalDraft(kind: kind, severity: severity, title: "Something happened")
    }

    @Test("emitting stores the event, updates unread counts, and dispatches channels")
    func emitStoresAndDispatches() {
        center.emit(draft(), from: .host)
        #expect(center.recent.count == 1)
        #expect(center.totalUnread == 1)
        #expect(center.unreadCounts[.host] == 1)
        #expect(deliverer.delivered.count == 1)
        #expect(deliverer.delivered[0].1.contains(.feed))
        #expect(deliverer.delivered[0].1.contains(.banner), "user is away, success promotes to banner")
    }

    @Test("a rejected draft dispatches nothing and stores nothing")
    func rejectionIsSilent() {
        center.emit(SignalDraft(kind: "Bad Kind", severity: .info, title: "x"), from: .host)
        #expect(center.recent.isEmpty)
        #expect(deliverer.delivered.isEmpty)
    }

    @Test("a run event routes like any other, now that the exemption is gone")
    func runEventsAreOrdinary() {
        center.emit(draft("run.finished"), from: .host)
        #expect(center.recent.count == 1)
        #expect(deliverer.delivered[0].1.contains(.banner),
                "the exemption used to strip this; stripping it now means no banner at all")
    }

    @Test("marking read clears the unread count")
    func markRead() {
        center.emit(draft(), from: .host)
        center.markAllRead(filter: .all)
        #expect(center.totalUnread == 0)
    }

    @Test("a muted source is still recorded but never delivered beyond the feed")
    func mutedSource() {
        center.rules.mutedSources.insert(.host)
        center.emit(draft(), from: .host)
        #expect(center.recent.count == 1)
        #expect(deliverer.delivered[0].1 == [.feed])
    }

    @Test("with no store the center degrades to memory and keeps delivering")
    func degradedMode() {
        let degraded = SignalCenter(
            store: nil,
            deliverer: deliverer,
            contextProvider: StubContext(deliveryContext: DeliveryContext(
                hostIsFrontmost: true, visibleAppIDs: [],
                systemDoNotDisturb: false, hostFocusMode: false)))
        #expect(degraded.isDegraded)
        degraded.emit(draft(), from: .host)
        #expect(degraded.recent.count == 1, "in-memory ring buffer still serves the feed")
        #expect(!deliverer.delivered.isEmpty, "routing is unaffected by a dead store")
    }

    @Test("the in-memory ring buffer is bounded")
    func ringBufferBounded() {
        let degraded = SignalCenter(store: nil, deliverer: deliverer,
                                    contextProvider: StubContext(deliveryContext: DeliveryContext(
                                        hostIsFrontmost: true, visibleAppIDs: [],
                                        systemDoNotDisturb: false, hostFocusMode: false)))
        for i in 0..<250 {
            degraded.emit(SignalDraft(kind: "test.event", severity: .info, title: "e\(i)"), from: .host)
        }
        #expect(degraded.recent.count == SignalCenter.degradedBufferLimit)
        #expect(degraded.recent.first?.title == "e249", "newest first")
    }
}
