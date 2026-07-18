// Sources/Ainkrad/Core/AgentKit/Commands/SlashCommand.swift
import Foundation

/// A slash command's dispatch outcome.
/// - `.handled(note:)`: the command ran; `note`, when non-nil, is surfaced to the
///   transcript as an assistant-role message (nil means the command was silent,
///   e.g. `/remember`, matching its pre-Task-16 behavior).
/// - `.notACommand`: the input didn't start with `/` (or matched nothing slash-like) —
///   the caller should proceed to send it as a normal prompt.
/// - `.sendAsPrompt`: the command rewrote the input into a prompt that should still be
///   sent to the model (reserved for future commands; no builtin uses it yet).
enum CommandResult: Sendable, Equatable {
    case handled(note: String?)
    case notACommand
    case sendAsPrompt
}

/// One registrable slash command. `handler` receives the raw argument string (text
/// after the command name, trimmed of the leading space) and the `AgentSession` it
/// is running against.
struct SlashCommand: Sendable {
    let name: String
    let summary: String
    let usage: String
    let handler: @MainActor (String, AgentSession) -> CommandResult
}
