// Tests/AinkradTests/SandboxProcessRunnerTests.swift
import Foundation
import Testing
@testable import Ainkrad

@Suite("SandboxProcessRunner")
struct SandboxProcessRunnerTests {
    private let runner = SandboxProcessRunner()

    @Test func capturesStdoutAndExitZero() async {
        let r = await runner.run(executable: "/bin/echo", arguments: ["hi"],
                                 workingDir: nil, timeout: 10)
        #expect(r.output.contains("hi"))
        #expect(r.exitCode == 0)
        #expect(r.isError == false)
        #expect(r.timedOut == false)
        #expect(r.unresponsive == false)
    }

    @Test func nonZeroExitIsError() async {
        let r = await runner.run(executable: "/bin/sh", arguments: ["-c", "exit 3"],
                                 workingDir: nil, timeout: 10)
        #expect(r.exitCode == 3)
        #expect(r.isError)
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutTerminatesLongRun() async {
        let r = await runner.run(executable: "/bin/sh", arguments: ["-c", "sleep 30"],
                                 workingDir: nil, timeout: 1)
        #expect(r.timedOut)
        #expect(r.isError)
    }

    @Test func honorsWorkingDir() async {
        let r = await runner.run(executable: "/bin/sh", arguments: ["-c", "pwd"],
                                 workingDir: "/tmp", timeout: 10)
        #expect(r.output.contains("/tmp"))
    }

    @Test func outputOverCapIsTruncated() async {
        var smallCapRunner = SandboxProcessRunner()
        smallCapRunner.maxOutputBytes = 16
        // Produce well over 16 bytes of output.
        let r = await smallCapRunner.run(executable: "/bin/sh",
                                         arguments: ["-c", "printf '0123456789abcdefghijklmnopqrstuvwxyz'"],
                                         workingDir: nil, timeout: 10)
        #expect(r.output.contains("[earlier output truncated]"))
    }

    @Test func spawnFailureReturnsFailedResultNotCrash() async {
        let r = await runner.run(executable: "/nonexistent/binary/does-not-exist",
                                 arguments: [], workingDir: nil, timeout: 10)
        #expect(r.exitCode == -1)
        #expect(r.isError)
    }
}
