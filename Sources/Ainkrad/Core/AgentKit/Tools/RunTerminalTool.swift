// Sources/Ainkrad/Core/AgentKit/Tools/RunTerminalTool.swift
import Foundation
import AinkradHostRuntime

/// Runs a shell command through the `ExecutionRouter` (M7 Slice 6) — the
/// router picks the backend + `SandboxProfile` for this tool's `trustTier`.
/// For the main interactive session (`.mainInteractive`, the default) this
/// resolves to `HostBackend`, byte-identical to the pre-router private
/// `Process` spawn this file used to own directly (now lifted verbatim into
/// `SandboxProcessRunner`). Then dispatches a best-effort `terminal.echo`
/// action over the v3 seam so the Terminal plugin renders the command +
/// output in the visible Block (nil result — no plugin — is ignored).
@MainActor
struct RunTerminalTool: AgentTool {
    /// Destructive substrings that force approval even in Full-auto.
    ///
    /// This list is a *heuristic for a confirmation prompt*, never a security
    /// boundary — see `isIrreversible` for why, and `effectiveTier` for what
    /// actually contains an unattended run.
    static let destructivePatterns = ["rm -rf", "rm -fr", "> /dev", "mkfs", "dd "]

    unowned let actionHub: AgentActionRegistryHub
    unowned let router: ExecutionRouter
    /// Trust tier this tool instance runs under. Only `.mainInteractive`
    /// (the default) is ever eligible to route to `HostBackend` — every
    /// other tier is sandboxed by the router (see `ExecutionRouter`).
    var trustTier: TrustTier = .mainInteractive
    /// The session's current permission mode, read per call. Nil (the default,
    /// used by tests and by non-session callers) behaves as `.ask` — i.e. as
    /// if a human is in the loop. See `effectiveTier`.
    var permissionMode: (@MainActor () -> AgentPermissionMode)? = nil
    var agentPolicy: AgentExecutionPolicy? = nil
    /// Wall-clock cap on a single command. Test seam kept from the
    /// pre-router tool: when set, overrides the resolved profile's
    /// `timeoutSeconds`. `nil` (the default) defers entirely to the
    /// profile's own timeout. Existing tests assign `tool.timeout = 1`.
    var timeout: TimeInterval? = nil
    /// Optional live-output sink (terminal-streaming): when set, each drained
    /// output snapshot is published to the ACTIVE tool call (the session calls
    /// `toolStream.begin(call.id)` at the pre-tool interception point). Nil keeps
    /// the pre-streaming capture-only behavior byte-identical.
    var toolStream: ToolStreamStore? = nil
    /// Force-kill handle for the live child process (terminal-streaming): when
    /// set, threaded into the `ExecutionRequest` so `SandboxProcessRunner.run`
    /// registers the spawned `Process` and `AgentSession.interrupt()` can kill
    /// it. Nil keeps the pre-Task-5 behavior byte-identical.
    var processController: TerminalProcessController? = nil

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

    /// The tier this call actually routes with.
    ///
    /// `.mainInteractive` is the one tier that can reach `HostBackend` — an
    /// unsandboxed `/bin/zsh -lc` with the user's full authority. That is
    /// justified *only* because a human approves each call. Full-auto removes
    /// the human, so it must also remove the host backend: the run is demoted
    /// to `.background`, which `ExecutionRouter` resolves to the sandboxed
    /// `workspace-write` profile.
    ///
    /// Before this, Full-auto's only backstop was `isIrreversible`'s
    /// five-substring list, and a prompt-injected model that phrased the
    /// command as `rm -r -f ~` (or `find ~ -delete`, or `curl x|sh`) ran it
    /// unsandboxed with no prompt.
    ///
    /// Non-main tiers are already sandboxed and pass through unchanged.
    var effectiveTier: TrustTier {
        guard trustTier == .mainInteractive else { return trustTier }
        return permissionMode?() == .fullAuto ? .background : trustTier
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let command = input["command"]?.stringValue, !command.isEmpty else {
            throw ToolError.message("run_terminal requires a non-empty \"command\".")
        }
        let workingDir = input["working_dir"]?.stringValue

        // Fail-closed: a router failure (backend unavailable/unregistered,
        // cloud not opted in, etc.) returns a failed tool result — it NEVER
        // falls back to an unsandboxed direct exec.
        let backend: any ExecutionBackend
        var profile: SandboxProfile
        do {
            (backend, profile) = try await router.route(tier: effectiveTier, policy: agentPolicy)
        } catch {
            return ToolResult(content: "$ \(command)\n[blocked: \(error)]", isError: true)
        }
        if let override = timeout { profile.resourceLimits.timeoutSeconds = Int(override) } // test seam

        // Bridge background-queue snapshots to the MainActor store. `toolStream`
        // is @MainActor; capture it in a Sendable box that hops each snapshot.
        let sink = toolStream
        // Capture the active call id ONCE, before execute() runs any awaits.
        // The session's pre-tool seam calls `toolStream.begin(call.id)` before
        // `execute` starts, so `activeID` is this call's id at this point. Binding
        // each snapshot to that id means a stale background-queue hop that lands
        // on the MainActor after `finish` + a successor `begin` (whose id no
        // longer matches `active`) is dropped instead of contaminating the next
        // call's buffer.
        let activeID = sink?.activeID
        var onOutput: (@Sendable (String) -> Void)? = nil
        if sink != nil, let activeID {
            onOutput = { snapshot in
                Task { @MainActor in sink?.appendActive("$ \(command)\n\(snapshot)", for: activeID) }
            }
        }
        let result: ExecutionResult
        do {
            result = try await backend.run(ExecutionRequest(
                command: command, workingDir: workingDir, profile: profile, onOutput: onOutput,
                processController: processController))
        } catch {
            return ToolResult(content: "$ \(command)\n[blocked: \(error)]", isError: true)
        }

        var output = result.output
        let content: String
        let timeoutDisplay = Double(profile.resourceLimits.timeoutSeconds)
        if result.unresponsive {
            output += "\n[terminated: exceeded \(timeoutDisplay)s; process unresponsive to SIGTERM/SIGINT]"
            content = "$ \(command)\n\(output)"
        } else if result.timedOut {
            output += "\n[terminated: exceeded \(timeoutDisplay)s]"
            content = "$ \(command)\n\(output)"
        } else {
            content = "$ \(command)\n\(output)\n[exit \(result.exitCode)]"
        }

        // Best-effort echo into the visible Terminal Block. Ignore a nil result
        // (no Terminal plugin registered) — the captured result above is what
        // returns to the agent.
        let echoInput = echoJSON(command: command, output: output)
        _ = await actionHub.invoke(actionID: "terminal.echo", input: echoInput)

        return ToolResult(content: content, isError: result.isError)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let command = input["command"]?.stringValue ?? "?"
        return ToolApprovalPreview(title: "Run terminal", summary: command, diff: nil)
    }

    /// Whether this call always requires human approval, in every mode.
    ///
    /// Delegates to `CommandRisk`, which tokenizes the command instead of
    /// substring-matching it — see that type for the list of bypasses the old
    /// five-element `destructivePatterns` scan missed. `destructivePatterns` is
    /// retained as a coarse belt-and-braces pass so the new analyzer can only
    /// ever *widen* what gets stopped, never narrow it.
    func isIrreversible(_ input: JSONValue) -> Bool {
        let raw = input["command"]?.stringValue ?? ""
        if CommandRisk.isIrreversible(raw) { return true }
        let lowered = raw.lowercased()
        return Self.destructivePatterns.contains { lowered.contains($0) }
    }

    private func echoJSON(command: String, output: String) -> String {
        let obj: [String: Any] = ["command": command, "output": output]
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
