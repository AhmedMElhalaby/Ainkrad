// Sources/Ainkrad/Core/AgentKit/Autonomy/TurnUndo.swift
import Foundation

/// Result of an `AgentSession.undoLastTurn()` call.
///
/// - `revertedEdits`: how many `EditJournal` entries were rolled back. `0` when
///   there was nothing to undo (empty turn stack) OR when the turn was refused
///   for being irreversible — undo is all-or-nothing per turn, so a refusal
///   never partially reverts the file-edit half of a turn.
/// - `irreversible`: human-readable notes for any tool call in the removed
///   turn that cannot actually be undone. A non-empty array here means the
///   turn was REFUSED (nothing was reverted, the transcript/edit-journal/turn
///   stack are all left exactly as they were).
struct TurnUndoSummary: Equatable {
    let revertedEdits: Int
    let irreversible: [String]
}

/// Pure, session-free classification of a turn's tool calls into "cannot be
/// undone" notes. `AgentSession.undoLastTurn()` consults this BEFORE touching
/// the edit journal or transcript, so an irreversible turn is refused rather
/// than partially unwound.
enum TurnUndo {
    /// Tool calls whose effects cannot be reverted by rewinding chat/edit/memory
    /// state — a shell command already ran, a git push already left the local
    /// repo, etc. Matched by tool NAME rather than by re-invoking
    /// `AgentTool.isIrreversible(_:)`, so classification stays a pure function
    /// of the transcript and needs no live tool registry to test.
    static let irreversibleTools: Set<String> = ["run_terminal"]

    /// Namespace whose tools are all treated as irreversible for undo purposes.
    ///
    /// Git used to appear here as the flat `git_op` name; it is now Git Mage's
    /// `mcp/gitmage/push`, `mcp/gitmage/commit`, … A name-only rule cannot ask an
    /// MCP descriptor for its `destructiveHint` (that would need a live registry,
    /// which is exactly what this type avoids), so the whole namespace is treated
    /// as unundoable. Deliberately over-broad and fail-safe in the right
    /// direction: the cost is refusing to unwind a turn that contained a
    /// read-only MCP call, versus the pre-existing cost of silently half-unwinding
    /// a turn that pushed. Narrowing this needs the descriptor, not a longer list.
    static let irreversibleToolPrefix = "mcp/"

    private static func isIrreversible(_ name: String) -> Bool {
        irreversibleTools.contains(name) || name.hasPrefix(irreversibleToolPrefix)
    }

    @MainActor
    static func classifyIrreversible(_ turnMessages: [AgentMessage]) -> [String] {
        var notes: [String] = []
        for message in turnMessages {
            for block in message.content {
                if case .toolUse(_, let name, _) = block, isIrreversible(name) {
                    notes.append("Cannot undo: \(name) already ran (side effects persist).")
                }
            }
        }
        return notes
    }
}
