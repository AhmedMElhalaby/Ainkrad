import Foundation

/// Rule-based `/compact` engine: collapses all but the most recent tail of a
/// conversation into a single synthetic summary message. `summarizeHeuristically`
/// provides the fallback summary text when no LLM summary is available (coordinates
/// with Slice 1's `MemoryConsolidator`, which follows the same rule-first approach;
/// an LLM summary hook is a fast-follow).
enum TranscriptCompactor {
    static func compact(_ messages: [AgentMessage], keepRecent: Int = 6, summary: String) -> [AgentMessage] {
        guard messages.count > keepRecent else { return messages }
        let tail = Array(messages.suffix(keepRecent))
        let head = AgentMessage(role: .assistant, text: "[Earlier conversation summarized]\n\(summary)")
        return [head] + tail
    }

    static func summarizeHeuristically(_ messages: [AgentMessage], maxChars: Int = 1200) -> String {
        let joined = messages.map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
        return joined.count > maxChars ? String(joined.suffix(maxChars)) : joined
    }
}
