import Foundation
import Testing
@testable import Ainkrad

@Suite("RunNotifier")
@MainActor
struct RunNotifierTests {
    @Test func recordingNotifierCapturesRuns() {
        let n = RecordingRunNotifier()
        var run = AgentRun(prompt: "x"); run.status = .done
        n.notifyCompleted(run)
        #expect(n.notified.count == 1)
        #expect(n.notified.first?.status == .done)
    }

    @Test func recordingNotifierCapturesMultipleRuns() {
        let n = RecordingRunNotifier()
        var run1 = AgentRun(prompt: "a"); run1.status = .done
        var run2 = AgentRun(prompt: "b"); run2.status = .failed
        n.notifyCompleted(run1)
        n.notifyCompleted(run2)
        #expect(n.notified.count == 2)
        #expect(n.notified.map(\.status) == [.done, .failed])
    }
}
