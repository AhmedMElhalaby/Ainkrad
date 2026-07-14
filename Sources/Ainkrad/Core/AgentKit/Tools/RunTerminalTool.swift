// Sources/Ainkrad/Core/AgentKit/Tools/RunTerminalTool.swift
import Foundation

/// Runs a shell command HOST-NATIVE (reliable stdout/stderr/exit capture) and
/// returns that captured result to the agent. Then dispatches a best-effort
/// `terminal.echo` action over the v3 seam so the Terminal plugin renders the
/// command + output in the visible Block (nil result — no plugin — is ignored).
@MainActor
struct RunTerminalTool: AgentTool {
    static let maxOutputBytes = 16 * 1024
    /// Destructive substrings that force approval even in Full-auto.
    static let destructivePatterns = ["rm -rf", "rm -fr", "> /dev", "mkfs", "dd "]

    unowned let actionHub: AgentActionRegistryHub
    /// Wall-clock cap on a single command. A hung process (`tail -f`, `yes`, a
    /// dev server, an interactive REPL) is force-terminated once this elapses
    /// rather than hanging the tool call forever. Injectable for tests.
    var timeout: TimeInterval = 30

    let name = "run_terminal"
    let description = "Run a shell command in a working directory and return its combined stdout+stderr and exit code."
    let permission: ToolPermissionClass = .write

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object(["type": .string("string"),
                                    "description": .string("The shell command to run (via zsh -lc).")]),
                "working_dir": .object(["type": .string("string"),
                                        "description": .string("Absolute working directory. Defaults to the user's home.")]),
            ]),
            "required": .array([.string("command")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let command = input["command"]?.stringValue, !command.isEmpty else {
            throw ToolError.message("run_terminal requires a non-empty \"command\".")
        }
        let workingDir = input["working_dir"]?.stringValue

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDir ?? NSHomeDirectory())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw ToolError.message("Could not launch the command: \(error.localizedDescription).")
        }

        // Read concurrently with the process running (never after
        // waitUntilExit) so a large or endless output can't deadlock the
        // pipe. A readability handler drains the pipe as data arrives and
        // stops accumulating (terminating the process) once `maxOutputBytes`
        // is exceeded, so a flood can't grow memory unbounded. A parallel
        // wall-clock timer force-terminates a process that never produces
        // EOF (`tail -f`, `yes`, a dev server, an interactive REPL).
        let handle = pipe.fileHandleForReading
        let accumulator = OutputAccumulator(cap: Self.maxOutputBytes)
        let timeout = self.timeout

        let (timedOut, unresponsive, exitStatus): (Bool, Bool, Int32) = await withCheckedContinuation { continuation in
            let gate = ContinuationGate(continuation: continuation)

            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                guard !chunk.isEmpty else { return } // EOF
                if !accumulator.append(chunk) {
                    process.terminate()
                }
            }

            process.terminationHandler = { proc in
                handle.readabilityHandler = nil
                gate.resume(exitStatus: proc.terminationStatus)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                // Mark timed-out *before* signaling, so there's no race with
                // `terminationHandler` firing and reading a stale flag.
                gate.markTimedOut()
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    guard process.isRunning else { return }
                    process.interrupt()
                    // Last-resort fallback: if the process ignores both
                    // signals, don't hang the tool call forever — resume with
                    // whatever output was captured. (`terminationHandler`
                    // firing later, if it ever does, is a no-op via the gate.)
                    // IMPORTANT: `Process.terminationStatus` traps with
                    // NSInvalidArgumentException if read while the process is
                    // still running. A command that traps both SIGTERM and
                    // SIGINT is still `isRunning` here, so it must NOT be
                    // read — resume as unresponsive instead.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        handle.readabilityHandler = nil
                        if process.isRunning {
                            gate.resumeUnresponsive()
                        } else {
                            gate.resume(exitStatus: process.terminationStatus)
                        }
                    }
                }
            }
        }

        let full = String(decoding: accumulator.snapshot(), as: UTF8.self)
        var output = boundedTail(full)
        let isError: Bool
        var content: String
        if unresponsive {
            // The process is still running and could not be killed — do NOT
            // read `terminationStatus` (traps on a live Process). Return
            // whatever output was captured with a clear marker instead of
            // crashing the host.
            output += "\n[terminated: exceeded \(timeout)s; process unresponsive to SIGTERM/SIGINT]"
            isError = true
            content = "$ \(command)\n\(output)"
        } else {
            if timedOut {
                output += "\n[terminated: exceeded \(timeout)s]"
                isError = true
            } else {
                isError = exitStatus != 0
            }
            content = "$ \(command)\n\(output)\n[exit \(exitStatus)]"
        }

        // Best-effort echo into the visible Terminal Block. Ignore a nil result
        // (no Terminal plugin registered) — the captured result above is what
        // returns to the agent.
        let echoInput = echoJSON(command: command, output: output)
        _ = await actionHub.invoke(actionID: "terminal.echo", input: echoInput)

        return ToolResult(content: content, isError: isError)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let command = input["command"]?.stringValue ?? "?"
        return ToolApprovalPreview(title: "Run terminal", summary: command, diff: nil)
    }

    func isIrreversible(_ input: JSONValue) -> Bool {
        let command = (input["command"]?.stringValue ?? "").lowercased()
        return Self.destructivePatterns.contains { command.contains($0) }
    }

    private func boundedTail(_ raw: String) -> String {
        let bytes = raw.utf8
        guard bytes.count > Self.maxOutputBytes else { return raw }
        let tail = String(decoding: Array(bytes.suffix(Self.maxOutputBytes)), as: UTF8.self)
        return "…[earlier output truncated]\n" + tail
    }

    private func echoJSON(command: String, output: String) -> String {
        let obj: [String: Any] = ["command": command, "output": output]
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Resumes a `CheckedContinuation` exactly once, even though the termination
/// handler and the timeout timer race each other from independent background
/// queues. Wrapping the resume-once state in a class (rather than a captured
/// local `var`) keeps every closure that touches it a plain capture of a
/// `Sendable` reference, satisfying Swift 6 strict concurrency at the
/// `@Sendable` closure boundaries `DispatchQueue`/`Process` require.
private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private var timedOut = false
    private let continuation: CheckedContinuation<(Bool, Bool, Int32), Never>

    init(continuation: CheckedContinuation<(Bool, Bool, Int32), Never>) {
        self.continuation = continuation
    }

    /// Marks the run as timed-out. Must be called (and observed to complete)
    /// *before* the caller signals the process, so `resume` — however it's
    /// triggered afterwards — always reads the up-to-date flag rather than
    /// racing a `terminationHandler` callback fired by that same signal.
    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    func resume(exitStatus: Int32) {
        lock.lock()
        let already = didResume
        didResume = true
        let out = timedOut
        lock.unlock()
        guard !already else { return }
        continuation.resume(returning: (out, false, exitStatus))
    }

    /// Resumes for the case where the process is still `isRunning` and
    /// could not be killed — never read `terminationStatus` here, it traps
    /// on a live `Process`. The exit status is meaningless in this case, so
    /// a sentinel value is passed through unread by the caller.
    func resumeUnresponsive() {
        lock.lock()
        let already = didResume
        didResume = true
        lock.unlock()
        guard !already else { return }
        continuation.resume(returning: (true, true, -1))
    }
}

/// Thread-safe byte accumulator for draining a process's output pipe from a
/// `FileHandle.readabilityHandler` (which fires on an arbitrary background
/// queue, outside of Swift concurrency). Stops growing once `cap` is reached
/// so a flooding command can't grow memory unbounded; `append` reports back
/// whether the caller should keep reading.
private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let cap: Int

    init(cap: Int) { self.cap = cap }

    /// Appends `chunk` unless the cap has already been hit. Returns `false`
    /// once the cap is reached (including on the call that crosses it), so
    /// the caller can terminate the process and stop reading.
    @discardableResult
    func append(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard data.count < cap else { return false }
        data.append(chunk)
        return data.count < cap
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
