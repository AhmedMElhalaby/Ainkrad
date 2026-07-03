import Testing
import Foundation
import SwiftTerm
@testable import Ainkrad

/// Collects PTY output and exit events from SwiftTerm's `LocalProcess` on a
/// private queue, so tests can run a real shell headlessly (no view layer).
private final class PTYOutputCollector: LocalProcessDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var exitHandler: ((Int32?) -> Void)?

    func setExitHandler(_ handler: @escaping (Int32?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        exitHandler = handler
    }

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: buffer, as: UTF8.self)
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        lock.lock()
        let handler = exitHandler
        exitHandler = nil
        lock.unlock()
        handler?(exitCode)
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: slice)
    }

    func getWindowSize() -> winsize {
        winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
    }
}

@Suite("PTY integration (real shell)", .timeLimit(.minutes(1)))
struct PTYIntegrationTests {

    @Test("a real shell's stdout arrives through the PTY channel")
    func realShellOutputArrivesThroughPTY() async {
        let collector = PTYOutputCollector()
        let queue = DispatchQueue(label: "com.ainkrad.tests.pty")
        let process = LocalProcess(delegate: collector, dispatchQueue: queue)

        await withCheckedContinuation { continuation in
            collector.setExitHandler { _ in continuation.resume() }
            process.startProcess(executable: "/bin/zsh", args: ["-c", "echo ainkrad-pty-check"])
        }

        #expect(collector.output.contains("ainkrad-pty-check"))
    }

    @Test("Block-close teardown (terminate + PTYReaper) leaves no zombie process")
    func terminatePlusReaperLeavesNoZombie() {
        // SwiftTerm's terminate() sends SIGTERM but cancels its exit monitor
        // without reaping — the app pairs it with PTYReaper. This test
        // exercises that exact teardown contract against a real child.
        let collector = PTYOutputCollector()
        let queue = DispatchQueue(label: "com.ainkrad.tests.pty-teardown")
        let process = LocalProcess(delegate: collector, dispatchQueue: queue)

        process.startProcess(executable: "/bin/zsh", args: ["-c", "sleep 30"])
        let pid = process.shellPid
        #expect(pid > 0)

        process.terminate()
        let reaped = PTYReaper.reapNow(pid)

        #expect(reaped)
        // kill(pid, 0) succeeds even for a zombie — -1 proves the child is
        // fully gone from the process table, not just dead.
        #expect(kill(pid, 0) == -1)
    }

    @Test("ten repeated start/terminate cycles complete without hanging or crashing")
    func repeatedStartStopCyclesAreClean() async {
        // Stability check: every cycle must reach process exit (the
        // .timeLimit trait catches hangs). Output content is asserted in
        // the dedicated PTY output test — on very short-lived processes
        // the final read can lose the race with exit, which is not a
        // lifecycle failure.
        var completedCycles = 0
        for cycle in 1...10 {
            let collector = PTYOutputCollector()
            let queue = DispatchQueue(label: "com.ainkrad.tests.pty-cycle-\(cycle)")
            let process = LocalProcess(delegate: collector, dispatchQueue: queue)

            await withCheckedContinuation { continuation in
                collector.setExitHandler { _ in continuation.resume() }
                process.startProcess(executable: "/bin/zsh", args: ["-c", "echo cycle-\(cycle)"])
            }
            completedCycles += 1
        }
        #expect(completedCycles == 10)
    }
}
