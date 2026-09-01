import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("SignalToastModel")
final class SignalToastStackModelTests {
    private func event(_ title: String, _ severity: SignalSeverity = .info) -> SignalEvent {
        SignalEvent(source: .host, kind: "test.event", severity: severity, title: title)
    }

    @Test("at most three toasts are visible; the rest become an overflow count")
    func caps() {
        let model = SignalToastModel()
        for i in 0..<6 { model.present(event("e\(i)")) }
        #expect(model.visible.count == 3)
        #expect(model.overflowCount == 3)
        #expect(model.visible.first?.title == "e2",
                "arrivals past the cap queue; they do not evict a toast being read")
    }

    @Test("dismissing promotes an overflowed toast into view")
    func dismissPromotes() {
        let model = SignalToastModel()
        for i in 0..<4 { model.present(event("e\(i)")) }
        #expect(model.overflowCount == 1)
        model.dismiss(id: model.visible[0].id)
        #expect(model.visible.count == 3)
        #expect(model.overflowCount == 0)
        #expect(model.visible.first?.title == "e3", "the promoted toast lands on top")
    }

    @Test("auto-dismiss delay scales with severity and failures never auto-dismiss")
    func autoDismissDelays() {
        #expect(SignalToastModel.autoDismissDelay(for: .info) == 4)
        #expect(SignalToastModel.autoDismissDelay(for: .success) == 4)
        #expect(SignalToastModel.autoDismissDelay(for: .warning) == 8)
        #expect(SignalToastModel.autoDismissDelay(for: .failure) == nil,
                "a failure the user never saw is the whole problem this feature solves")
    }

    @Test("a failure arriving past the cap displaces the least-severe toast")
    func severityDisplacesWeakest() {
        let model = SignalToastModel()
        for i in 0..<3 { model.present(event("info\(i)", .info)) }
        model.present(event("BUILD FAILED", .failure))

        #expect(model.visible.first?.title == "BUILD FAILED",
                "the failure must not sit behind chatty info toasts")
        #expect(model.visible.count == 3)
        #expect(model.overflowCount == 1, "the displaced info toast goes back to the queue")
        #expect(!model.visible.contains { $0.severity == .info && $0.title == "info0" }
                || model.visible.filter { $0.severity == .info }.count == 2)
    }

    @Test("a failure on screen is never displaced, not even by another failure")
    func failuresAreNeverDisplaced() {
        let model = SignalToastModel()
        for i in 0..<3 { model.present(event("fail\(i)", .failure)) }
        model.present(event("newest failure", .failure))
        #expect(model.overflowCount == 1, "equal severity queues rather than displacing")
        #expect(model.visible.allSatisfy { $0.title != "newest failure" })
    }

    @Test("a less severe arrival still queues")
    func lessSevereQueues() {
        let model = SignalToastModel()
        for i in 0..<3 { model.present(event("warn\(i)", .warning)) }
        model.present(event("chatter", .info))
        #expect(model.overflowCount == 1)
        #expect(model.visible.allSatisfy { $0.severity == .warning })
    }

    @Test("presenting the same event twice does not stack duplicates")
    func idempotentPresent() {
        let model = SignalToastModel()
        let e = event("once")
        model.present(e)
        model.present(e)
        #expect(model.visible.count == 1)
    }
}
