// Sources/Ainkrad/Core/AgentKit/Commands/CommandRegistry.swift
import Foundation

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
            SlashCommand(name: "compact", summary: "Compact the transcript (coming soon)", usage: "/compact") { _, _ in
                .handled(note: "Transcript compaction isn't implemented yet.")
            },
            SlashCommand(name: "export", summary: "Export the transcript (coming soon)", usage: "/export") { _, _ in
                .handled(note: "Transcript export isn't implemented yet.")
            },
        ]
    }
}
