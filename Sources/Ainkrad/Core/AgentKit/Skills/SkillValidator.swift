import Foundation

enum SkillValidationIssue: Equatable {
    case unsafeName(String)
    case emptyBody
    case emptyDescription
}

/// Validates a parsed `Skill` before it becomes active. A skill with any issue
/// is skipped by `SkillRegistry` (never fatal) and surfaced in the manager.
enum SkillValidator {
    /// The `name` is also a directory name and namespace segment — keep it a
    /// lowercase slug so it can never traverse the filesystem.
    static func isSafeName(_ name: String) -> Bool {
        guard let first = name.first, first.isLowercase || first.isNumber else { return false }
        return name.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
    }

    static func validate(_ skill: Skill) -> [SkillValidationIssue] {
        var issues: [SkillValidationIssue] = []
        if !isSafeName(skill.name) { issues.append(.unsafeName(skill.name)) }
        if skill.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptyBody) }
        if skill.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyDescription)
        }
        return issues
    }
}
