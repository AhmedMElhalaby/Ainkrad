import Foundation

/// A passive, per-turn hint that the just-completed procedure looked reusable.
/// Presentation-only state on `AgentSession`; never auto-acts. `toolNames` is
/// the distinct tool sequence the advisor saw, used to seed the reflection
/// directive when the user accepts.
struct SkillSuggestion: Equatable {
    let toolNames: [String]
}
