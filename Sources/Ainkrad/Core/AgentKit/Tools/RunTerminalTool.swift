// Sources/Ainkrad/Core/AgentKit/Tools/RunTerminalTool.swift
import Foundation

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
    static let destructivePatterns = ["rm -rf", "rm -fr", "> /dev", "mkfs", "dd "]

    unowned let actionHub: AgentActionRegistryHub
    unowned let router: ExecutionRouter
    /// Trust tier this tool instance runs under. Only `.mainInteractive`
    /// (the default) is ever eligible to route to `HostBackend` — every
    /// other tier is sandboxed by the router (see `ExecutionRouter`).
    var trustTier: TrustTier = .mainInteractive
    var agentPolicy: AgentExecutionPolicy? = nil
    /// Wall-clock cap on a single command. Test seam kept from the
    /// pre-router tool: when set, overrides the resolved profile's
    /// `timeoutSeconds`. `nil` (the default) defers entirely to the
    /// profile's own timeout. Existing tests assign `tool.timeout = 1`.
    var timeout: TimeInterval? = nil

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

        // Fail-closed: a router failure (backend unavailable/unregistered,
        // cloud not opted in, etc.) returns a failed tool result — it NEVER
        // falls back to an unsandboxed direct exec.
        let backend: any ExecutionBackend
        var profile: SandboxProfile
        do {
            (backend, profile) = try await router.route(tier: trustTier, policy: agentPolicy)
        } catch {
            return ToolResult(content: "$ \(command)\n[blocked: \(error)]", isError: true)
        }
        if let override = timeout { profile.resourceLimits.timeoutSeconds = Int(override) } // test seam

        let result: ExecutionResult
        do {
            result = try await backend.run(ExecutionRequest(command: command, workingDir: workingDir, profile: profile))
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

    func isIrreversible(_ input: JSONValue) -> Bool {
        let command = (input["command"]?.stringValue ?? "").lowercased()
        return Self.destructivePatterns.contains { command.contains($0) }
    }

    private func echoJSON(command: String, output: String) -> String {
        let obj: [String: Any] = ["command": command, "output": output]
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
