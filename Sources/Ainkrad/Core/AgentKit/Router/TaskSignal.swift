import Foundation

/// Per-turn features the Model Router uses to filter and order candidates.
/// Built from the transcript + attachments each turn (see Task 13's `ModelRouter`).
struct TaskSignal: Equatable, Sendable {
    var estimatedInputTokens: Int
    var needsVision: Bool
    var needsTools: Bool
    var reasoningHeavy: Bool
}
