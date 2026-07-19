import Foundation
import AinkradAppKit

/// Injects a cheap index (name + description) of the active skills into the
/// agent's context each turn via `AgentContextRegistryHub`. Full instructions
/// stay on disk and load on demand through `use_skill` (progressive disclosure),
/// so a large skill library never bloats the prompt budget. Mirrors
/// `MemoryContextSource`'s pattern exactly: a pure function producing an
/// `AgentContextSnapshot?`, gated centrally by `AgentContextSettingsStore` via
/// `kind` (no per-source privacy check needed here).
enum SkillIndexContextSource {
    static let kind = "skills-index"

    @MainActor
    static func snapshot(from registry: SkillRegistry) -> AgentContextSnapshot? {
        let skills = registry.skills
        guard !skills.isEmpty else { return nil }
        // `registry.skills` is already sorted by name (see SkillRegistry.reload),
        // so the index is deterministic without re-sorting here.
        let list = skills.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        let body = """
        These skills encode reusable procedures. When one is relevant, call the \
        `use_skill` tool with its name to load the full instructions before acting.

        \(list)
        """
        return AgentContextSnapshot(kind: kind, title: "Available Skills", text: body)
    }
}
