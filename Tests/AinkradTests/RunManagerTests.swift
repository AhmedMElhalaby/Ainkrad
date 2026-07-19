import Foundation
import Testing
@testable import Ainkrad

@Suite("RunManager", .timeLimit(.minutes(1)))
@MainActor
struct RunManagerTests {
    /// Completes immediately with a fixed result.
    final class InstantRunner: AgentRunRunner {
        func execute(prompt: String, appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
            appendLog("ran \(prompt)")
            return .success("result:\(prompt)")
        }
    }

    /// Suspends until `release()` so concurrency can be observed mid-flight.
    final class GatedRunner: AgentRunRunner {
        private(set) var started = 0
        private var conts: [CheckedContinuation<Void, Never>] = []
        func execute(prompt: String, appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
            started += 1
            await withCheckedContinuation { conts.append($0) }
            return .success("done")
        }
        func releaseAll() { conts.forEach { $0.resume() }; conts.removeAll() }
    }

    @Test func runCompletesPersistsAndNotifies() async {
        let p = InMemoryPersistenceStore()
        let notifier = RecordingRunNotifier()
        let mgr = RunManager(persistence: p, runner: InstantRunner(), notifier: notifier)
        let run = mgr.enqueue(prompt: "task-a")
        // Let the run task settle.
        await Task.yield(); await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let reloaded = RunManager(persistence: p, runner: InstantRunner())
        let stored = reloaded.runs.first { $0.id == run.id }
        #expect(stored?.status == .done)
        #expect(stored?.result == "result:task-a")
        #expect(notifier.notified.contains { $0.id == run.id })
    }

    @Test func relaunchMarksRunningAsInterrupted() {
        let p = InMemoryPersistenceStore()
        var doc = AgentRunsDocument()
        doc.runs = [AgentRun(prompt: "crashed", status: .running)]
        p.save(doc)
        let mgr = RunManager(persistence: p, runner: InstantRunner())
        #expect(mgr.runs.first?.status == .interrupted)
    }

    @Test func concurrencyCapBoundsRunning() async {
        let runner = GatedRunner()
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: runner, maxConcurrent: 2)
        mgr.enqueue(prompt: "1"); mgr.enqueue(prompt: "2"); mgr.enqueue(prompt: "3")
        await Task.yield(); await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(runner.started == 2)                                   // third is still queued
        #expect(mgr.runs.filter { $0.status == .running }.count == 2)
        runner.releaseAll()
    }

    @Test func pauseKeepsAQueuedRunFromStarting() async {
        let runner = GatedRunner()
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: runner, maxConcurrent: 1)
        let a = mgr.enqueue(prompt: "a")
        let b = mgr.enqueue(prompt: "b")
        mgr.pause(b.id)
        await Task.yield(); try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(mgr.runs.first { $0.id == b.id }?.status == .paused)
        #expect(runner.started == 1)                                   // only `a`
        runner.releaseAll()
        _ = a
    }

    @Test func stopFreesASlotForTheNextQueuedRun() async {
        let runner = GatedRunner()
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: runner, maxConcurrent: 1)
        let a = mgr.enqueue(prompt: "a")
        let b = mgr.enqueue(prompt: "b")
        await Task.yield(); try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(mgr.runs.first { $0.id == a.id }?.status == .running)
        mgr.stop(a.id)
        await Task.yield(); try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(mgr.runs.first { $0.id == a.id }?.status == .interrupted)
        #expect(mgr.runs.first { $0.id == b.id }?.status == .running)  // slot freed, next started
        #expect(mgr.runs.filter { $0.status == .running }.count == 1)  // cap never exceeded
        runner.releaseAll()
    }
}
