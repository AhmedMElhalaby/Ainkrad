import Testing
import Foundation
import AinkradSignal
import AinkradHostRuntime
@testable import Ainkrad

/// The M1 exemption, exercised through the REAL `RunManager` completion path
/// rather than by calling `SignalCenter.emit` directly.
///
/// This is the milestone's highest-risk behaviour: `RunNotifier` and Signal both
/// know when a run finishes, so the failure mode is two macOS banners for one
/// run. Asserting it at the `emit` seam only proves routing; this drives
/// `enqueue` → runner → `finish(_:outcome:)` and checks both notification paths
/// at once.
@MainActor
@Suite("Exactly one banner per completed run")
final class RunBannerIntegrationTests {
    private final class InstantRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?,
                     appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
            .success("done")
        }
    }
    private final class FailingRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?,
                     appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
            .failure("exploded")
        }
    }
    /// Stands in for `UserNotificationRunNotifier`, counting the banners it
    /// would have posted.
    private final class SpyRunNotifier: RunNotifier {
        private(set) var notified: [AgentRun] = []
        func notifyCompleted(_ run: AgentRun) { notified.append(run) }
    }
    private final class SpyDeliverer: SignalDeliverer {
        private(set) var delivered: [(SignalEvent, Set<DeliveryChannel>)] = []
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
            delivered.append((event, channels))
        }
    }
    /// The user has looked away — the situation in which a run banner matters,
    /// and the one where a duplicate would be most obvious.
    private struct AwayContext: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: false, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    private func waitForCompletion(_ manager: RunManager, id: UUID) async {
        for _ in 0..<200 {
            if let run = manager.runs.first(where: { $0.id == id }),
               run.status == .done || run.status == .failed || run.status == .interrupted {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("run did not finish within the timeout")
    }

    private func makeCenter(_ deliverer: SpyDeliverer) throws -> (SignalCenter, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        return (SignalCenter(store: try SignalStore(url: url),
                             deliverer: deliverer, contextProvider: AwayContext()), url)
    }

    @Test("a successful run posts one legacy banner and zero Signal banners")
    func successfulRun() async throws {
        let deliverer = SpyDeliverer()
        let (center, url) = try makeCenter(deliverer)
        defer { try? FileManager.default.removeItem(at: url) }
        let notifier = SpyRunNotifier()
        let manager = RunManager(persistence: InMemoryPersistenceStore(),
                                 runner: InstantRunner(),
                                 notifier: notifier,
                                 signalCenter: center)

        let run = manager.enqueue(prompt: "do the thing", origin: .chat)
        await waitForCompletion(manager, id: run.id)

        #expect(notifier.notified.count == 1, "RunNotifier owns the banner in M1")
        #expect(center.recent.count == 1, "and the feed records it regardless")
        #expect(center.recent.first?.kind == "run.finished")
        #expect(deliverer.delivered.count == 1)
        let channels = deliverer.delivered[0].1
        #expect(!channels.contains(.banner),
                "TWO banners for one run is the regression this milestone risks")
        #expect(channels.contains(.feed))
    }

    @Test("a failed run behaves the same way")
    func failedRun() async throws {
        let deliverer = SpyDeliverer()
        let (center, url) = try makeCenter(deliverer)
        defer { try? FileManager.default.removeItem(at: url) }
        let notifier = SpyRunNotifier()
        let manager = RunManager(persistence: InMemoryPersistenceStore(),
                                 runner: FailingRunner(),
                                 notifier: notifier,
                                 signalCenter: center)

        let run = manager.enqueue(prompt: "break the thing", origin: .chat)
        await waitForCompletion(manager, id: run.id)

        #expect(notifier.notified.count == 1)
        #expect(center.recent.first?.kind == "run.failed")
        #expect(center.recent.first?.severity == .failure)
        #expect(!deliverer.delivered[0].1.contains(.banner))
        #expect(deliverer.delivered[0].1.contains(.sound), "a failure still makes a sound")
    }

    /// Proves the three assertions above are actually sensitive to the
    /// exemption rather than passing for some unrelated reason — and pins M2's
    /// target state, where `RunNotifier` is gone and this banner must arrive
    /// through Signal instead. If this test ever fails, deleting `RunNotifier`
    /// would silently cost the user a notification.
    @Test("with the exemption lifted, the banner arrives through Signal instead")
    func exemptionLiftedRoutesTheBanner() async throws {
        let deliverer = SpyDeliverer()
        let (center, url) = try makeCenter(deliverer)
        defer { try? FileManager.default.removeItem(at: url) }
        center.rules.suppressBannerForHostRuns = false   // M2's state

        let manager = RunManager(persistence: InMemoryPersistenceStore(),
                                 runner: InstantRunner(),
                                 notifier: nil,
                                 signalCenter: center)
        let run = manager.enqueue(prompt: "do the thing", origin: .chat)
        await waitForCompletion(manager, id: run.id)

        #expect(deliverer.delivered.count == 1)
        #expect(deliverer.delivered[0].1.contains(.banner),
                "with no legacy notifier, Signal must be the one posting it")
    }

    @Test("two runs produce two feed rows and two legacy banners, not four")
    func twoRuns() async throws {
        let deliverer = SpyDeliverer()
        let (center, url) = try makeCenter(deliverer)
        defer { try? FileManager.default.removeItem(at: url) }
        let notifier = SpyRunNotifier()
        let manager = RunManager(persistence: InMemoryPersistenceStore(),
                                 runner: InstantRunner(),
                                 notifier: notifier,
                                 signalCenter: center)

        let first = manager.enqueue(prompt: "one", origin: .chat)
        let second = manager.enqueue(prompt: "two", origin: .chat)
        await waitForCompletion(manager, id: first.id)
        await waitForCompletion(manager, id: second.id)

        #expect(notifier.notified.count == 2)
        #expect(center.recent.count == 2, "distinct runs must not coalesce into one row")
        #expect(deliverer.delivered.allSatisfy { !$0.1.contains(.banner) })
    }
}
