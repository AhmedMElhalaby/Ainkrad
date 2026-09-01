import Testing
import Foundation
import AinkradSignal
import AinkradAppKit
@testable import Ainkrad
@testable import AinkradHostRuntime

@MainActor
@Suite("HostSignalEmitter")
final class HostSignalEmitterTests {
    private final class SpyDeliverer: SignalDeliverer {
        var delivered: [(SignalEvent, Set<DeliveryChannel>)] = []
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
            delivered.append((event, channels))
        }
    }
    private struct PresentContext: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: true, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    private let url: URL
    private let center: SignalCenter
    private let hub: SignalEmitterHub
    private let deliverer = SpyDeliverer()

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        center = SignalCenter(store: try SignalStore(url: url),
                              deliverer: deliverer, contextProvider: PresentContext())
        // The hub records through the `SignalEmitting` sink, which the feed
        // conforms to — `AinkradHostRuntime` cannot see `SignalCenter`.
        hub = SignalEmitterHub(sink: center)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @Test("an app's event is stamped with that app's id")
    func stampsAppID() {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        raven.emit(kind: "build.failed", severity: .failure, title: "Build failed")
        #expect(center.recent.count == 1)
        #expect(center.recent[0].source == .app(appID: "raven"))
    }

    @Test("two apps cannot see or attribute each other's events")
    func isolation() {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        let quest = HostSignalEmitter(appID: "quest", hub: hub)
        raven.emit(kind: "build.failed", severity: .failure, title: "R")
        quest.emit(kind: "session.done", severity: .success, title: "Q")

        #expect(raven.own(limit: 10).map(\.title) == ["R"])
        #expect(quest.own(limit: 10).map(\.title) == ["Q"])
        #expect(center.recent.count == 2, "the host still sees both")
    }

    @Test("own(limit:) never returns another app's events even at a large limit")
    func ownIsScoped() {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        HostSignalEmitter(appID: "quest", hub: hub)
            .emit(kind: "test.event", severity: .info, title: "Q")
        #expect(raven.own(limit: 1000).isEmpty)
    }

    @Test("an invalid kind is swallowed, not thrown, and stores nothing")
    func invalidKindIsSilent() {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        raven.emit(kind: "Not A Kind", severity: .info, title: "t")
        #expect(center.recent.isEmpty)
    }

    @Test("a registered action handler fires when the host invokes it")
    func actionHandler() async {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        var fired = false
        _ = raven.handleAction("retry") { fired = true }
        await hub.invoke(actionID: "retry", appID: "raven")
        #expect(fired)
    }

    @Test("invoking an action for the wrong app does nothing")
    func actionsAreScoped() async {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        var fired = false
        _ = raven.handleAction("retry") { fired = true }
        await hub.invoke(actionID: "retry", appID: "quest")
        #expect(!fired, "one app's action id must not shadow another's")
    }

    @Test("a removed handler no longer fires")
    func removeHandler() async {
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        var fired = false
        let token = raven.handleAction("retry") { fired = true }
        raven.removeActionHandler(token)
        await hub.invoke(actionID: "retry", appID: "raven")
        #expect(!fired)
    }

    @Test("forging another app's source is not expressible")
    func forgeryIsInexpressible() {
        // `PluginSignalEmitter` has no `source` parameter and `HostSignalEmitter`
        // binds the id at construction, so there is no code path by which an app
        // can emit as another. This test pins the property; the compiler enforces it.
        let raven = HostSignalEmitter(appID: "raven", hub: hub)
        raven.emit(kind: "test.event", severity: .info, title: "t")
        #expect(center.recent.allSatisfy { $0.source == .app(appID: "raven") })
    }
}
