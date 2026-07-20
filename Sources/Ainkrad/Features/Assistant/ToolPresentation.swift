import Foundation

/// Token-free tint selector so the mapping stays pure and unit-testable; the
/// view resolves it to a real `DesignTokens` color.
enum ToolTint: Equatable { case primary, secondary }

/// Pure `tool name → visual identity` mapping for transcript tool cards.
/// No SwiftUI, no `AppEnvironment` — unit-tested like `CommandPaletteView.filter`.
struct ToolPresentation: Equatable {
    let icon: String
    let tint: ToolTint
    let label: String

    static func `for`(toolName name: String) -> ToolPresentation {
        let (icon, tint) = iconAndTint(for: name)
        return ToolPresentation(icon: icon, tint: tint, label: humanize(name))
    }

    /// "run_terminal" → "Run terminal". Underscores → spaces, sentence-cased.
    static func humanize(_ name: String) -> String {
        guard name.contains("_") else { return name }
        let spaced = name.replacingOccurrences(of: "_", with: " ").lowercased()
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private static func iconAndTint(for name: String) -> (String, ToolTint) {
        if name.hasPrefix("mcp__") { return ("puzzlepiece.extension", .secondary) }
        switch name {
        case "run_terminal":        return ("terminal", .secondary)
        case "git_op":              return ("arrow.triangle.branch", .secondary)
        case "workspace_control":   return ("macwindow", .secondary)
        case "Edit", "Write", "str_replace": return ("pencil", .primary)
        case "Read":                return ("doc.text", .secondary)
        default:                    return ("wrench.and.screwdriver", .secondary)
        }
    }
}
