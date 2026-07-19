// Sources/Ainkrad/Core/AgentKit/Commands/CommandRegistry.swift
import Foundation
import AppKit

/// Single slash-command dispatch path. `AgentSession.send` runs every input through
/// this registry first — this is also where Slice 1's old `/remember ` prefix
/// intercept in `AgentSession.send` was migrated to (see `BuiltinCommands.remember`),
/// so there is exactly one place that recognizes a leading `/`.
@MainActor
final class CommandRegistry {
    private var commands: [String: SlashCommand]
    private var order: [String]

    init(builtins: [SlashCommand]) {
        commands = [:]
        order = []
        for c in builtins where commands[c.name] == nil { commands[c.name] = c; order.append(c.name) }
    }

    /// Appends (or overwrites) a command — the seam Slice 4 skill commands register
    /// through, after the builtins are constructed.
    func register(_ c: SlashCommand) {
        if commands[c.name] == nil { order.append(c.name) }
        commands[c.name] = c
    }

    /// Removes a previously `register(_:)`ed command by name. Host-internal,
    /// additive seam for the Skills manager UI (Task 13): re-syncing the live
    /// skill `/name` commands after a runtime bind/unbind needs to be able to
    /// drop a name that no longer has a binding, not just overwrite it. A
    /// no-op when `name` isn't registered — in particular, never removes a
    /// builtin unless a caller explicitly names one (the manager only ever
    /// passes skill-command names it tracked itself).
    func unregister(name: String) {
        guard commands.removeValue(forKey: name) != nil else { return }
        order.removeAll { $0 == name }
    }

    func all() -> [SlashCommand] { order.compactMap { commands[$0] } }

    func parse(_ input: String) -> (command: SlashCommand, args: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        let parts = trimmed.dropFirst().split(separator: " ", maxSplits: 1)
        guard let name = parts.first.map(String.init), let c = commands[name] else { return nil }
        return (c, parts.count > 1 ? String(parts[1]) : "")
    }

    func run(_ input: String, on session: AgentSession) -> CommandResult {
        guard let (command, args) = parse(input) else {
            return input.trimmingCharacters(in: .whitespaces).hasPrefix("/") ? .handled(note: "Unknown command.") : .notACommand
        }
        return command.handler(args, session)
    }
}

/// Factory for the host's built-in commands, constructed once in `AppEnvironment`
/// (they close over `runtime`/`usage`/`router`/`catalog`) and handed to
/// `CommandRegistry(builtins:)`.
enum BuiltinCommands {
    /// Every builtin command name, derived from `make(...)` itself (never a
    /// hand-maintained duplicate list, so it can't drift as builtins are
    /// added/renamed). A skill-bound `/name` must never collide with one of
    /// these — see `SkillCommandStore.isValidCommandName`.
    static var reservedNames: Set<String> {
        Set(make(runtime: nil, usage: nil, router: nil, catalog: nil).map(\.name))
    }

    static func make(runtime: RuntimeOptionsStore?, usage: UsageTracker?,
                     router: ModelRouter?, catalog: ModelCatalog?) -> [SlashCommand] {
        [
            SlashCommand(name: "new", summary: "Start a new session", usage: "/new") { _, session in
                session.reset()
                runtime?.resetForNewSession()
                return .handled(note: nil)
            },
            SlashCommand(name: "reset", summary: "Start a new session", usage: "/reset") { _, session in
                session.reset()
                runtime?.resetForNewSession()
                return .handled(note: nil)
            },
            SlashCommand(name: "remember", summary: "Save a fact to memory", usage: "/remember <fact>") { args, session in
                let fact = args.trimmingCharacters(in: .whitespaces)
                guard !fact.isEmpty else { return .handled(note: "Usage: /remember <fact>") }
                session.remember(fact)
                return .handled(note: nil)
            },
            SlashCommand(name: "model", summary: "Pin the model used for this session", usage: "/model <id>") { args, _ in
                let id = args.trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty else { return .handled(note: "Usage: /model <id>") }
                guard let runtime else { return .handled(note: "Model pinning is unavailable right now.") }
                if ["auto", "off", "none"].contains(id.lowercased()) {
                    runtime.pinModel(nil)
                    return .handled(note: "Router is now choosing the model each turn (Auto).")
                }
                runtime.pinModel(id)
                return .handled(note: "Pinned model to \(id) for this session.")
            },
            SlashCommand(name: "think", summary: "Set the reasoning-effort level", usage: "/think <low|medium|high|max>") { args, session in
                let level = args.trimmingCharacters(in: .whitespaces).lowercased()
                guard ["low", "medium", "high", "max"].contains(level) else {
                    return .handled(note: "Usage: /think <low|medium|high|max>")
                }
                guard let runtime else { return .handled(note: "Think-level is unavailable right now.") }
                runtime.setThinkLevel(level)
                // Only ClaudeProvider honors `effort` (Claude-only `output_config.effort`);
                // OpenAI-compatible/Gemini ignore it entirely — surface that honestly
                // instead of silently persisting a no-op setting.
                let modelID = session.activeModelIDForCommands()
                let capable = catalog?.descriptor(for: modelID)?.capabilities.contains(.reasoningEffort) ?? true
                if capable {
                    return .handled(note: "Reasoning effort set to \(level).")
                }
                return .handled(note: "Reasoning effort set to \(level), but \(modelID) doesn't support adjustable effort — no effect.")
            },
            SlashCommand(name: "verbose", summary: "Toggle verbose transcript detail", usage: "/verbose on|off") { args, _ in
                switch args.trimmingCharacters(in: .whitespaces).lowercased() {
                case "on": runtime?.setVerbose(true); return .handled(note: "Verbose mode on.")
                case "off": runtime?.setVerbose(false); return .handled(note: "Verbose mode off.")
                default: return .handled(note: "Usage: /verbose on|off")
                }
            },
            SlashCommand(name: "trace", summary: "Toggle router/tool trace detail", usage: "/trace on|off") { args, _ in
                switch args.trimmingCharacters(in: .whitespaces).lowercased() {
                case "on": runtime?.setTrace(true); return .handled(note: "Trace mode on.")
                case "off": runtime?.setTrace(false); return .handled(note: "Trace mode off.")
                default: return .handled(note: "Usage: /trace on|off")
                }
            },
            SlashCommand(name: "usage", summary: "Show token/cost usage", usage: "/usage") { _, _ in
                guard let usage else { return .handled(note: "Usage tracking is unavailable right now.") }
                let (cumulative, costUSD, savingsUSD) = usage.cumulative()
                // Gate each dollar figure on `> 0` — `UsageTracker` only accumulates
                // cost when `ModelPriceTable` knows the model's price, so a `0` here
                // means "never priced", NEVER a real zero-dollar turn. Mirrors
                // `formattedUsageCost`'s `cost > 0` convention (`UsageDashboardView.swift`)
                // so the text note and the dashboard never disagree.
                let sessionCost = usage.sessionCostUSD > 0 ? "$" + String(format: "%.4f", usage.sessionCostUSD) : "cost unknown"
                let lifeCost = costUSD > 0 ? "$" + String(format: "%.2f", costUSD) : "cost unknown"
                let note = """
                Session: \(usage.session.input) in / \(usage.session.output) out · \(sessionCost)
                Lifetime: \(cumulative.input) in / \(cumulative.output) out · \(lifeCost) (saved $\(String(format: "%.2f", savingsUSD)))
                """
                return .handled(note: note)
            },
            // `/compact` and `/export` both need LIVE session state (the transcript),
            // which `SlashCommand.handler` already receives as its `session` argument —
            // that existing seam is the cleanest way to reach it, so neither command
            // needs `BuiltinCommands.make` to take an `AgentSession` dependency itself.
            SlashCommand(name: "compact", summary: "Summarize older messages to shrink the transcript", usage: "/compact") { _, session in
                // Guard against mid-turn execution: `replaceMessages` overwrites
                // `session.messages` wholesale, so compacting while a turn is
                // in flight (thinking/streaming/tool-calling/awaiting approval)
                // would clobber in-flight appends with a stale pre-turn snapshot.
                // Mirrors the same state set `AgentSession.send`'s re-entrancy
                // guard treats as "busy".
                switch session.state {
                case .thinking, .streaming, .callingTool, .awaitingApproval:
                    return .handled(note: "Can't compact while a turn is in progress — stop or finish it first.")
                case .idle, .failed:
                    break
                }
                let originalCount = session.messages.count
                let keepRecent = 6
                guard originalCount > keepRecent else {
                    return .handled(note: "Nothing to compact yet — only \(originalCount) message\(originalCount == 1 ? "" : "s") in this session.")
                }
                let summary = TranscriptCompactor.summarizeHeuristically(session.messages)
                let compacted = TranscriptCompactor.compact(session.messages, keepRecent: keepRecent, summary: summary)
                session.replaceMessages(compacted)
                let summarizedCount = originalCount - keepRecent
                return .handled(note: "Compacted \(summarizedCount) earlier message\(summarizedCount == 1 ? "" : "s") into a summary; kept the most recent \(keepRecent).")
            },
            SlashCommand(name: "export", summary: "Copy the transcript to the clipboard as Markdown", usage: "/export") { _, session in
                guard !session.messages.isEmpty else { return .handled(note: "Nothing to export yet.") }
                let rendered = ConversationExporter.export(session.messages, format: .markdown)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(rendered, forType: .string)
                return .handled(note: "Copied the transcript to your clipboard as Markdown (\(rendered.count) characters).")
            },
            SlashCommand(name: "undo", summary: "Undo the last turn's file edits + transcript", usage: "/undo") { _, session in
                let summary = session.undoLastTurn()
                if !summary.irreversible.isEmpty {
                    let ran = summary.irreversible.joined(separator: " ")
                    return .handled(note: "This turn can't be undone — it ran a tool with irreversible effects. \(ran)")
                }
                if summary.revertedEdits == 0 {
                    return .handled(note: "Nothing to undo.")
                }
                let plural = summary.revertedEdits == 1 ? "edit" : "edits"
                return .handled(note: "Undid the last turn — reverted \(summary.revertedEdits) file \(plural).")
            },
            SlashCommand(name: "retry", summary: "Re-run the last user prompt", usage: "/retry") { _, session in
                session.retryLastTurn()
                return .handled(note: nil)
            },
        ]
    }
}
