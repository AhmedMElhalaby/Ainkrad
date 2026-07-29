import AinkradAppKitContract

/// Retired paths resolve forward rather than dead-ending. The IA restructure
/// moved settings people had muscle memory for; a stale deep-link or a
/// persisted selection from an older build should still land somewhere sane.
///
/// Entries are permanent. Deleting one breaks links that may exist in saved
/// sessions, docs, or assistant transcripts.
enum SettingsPathAliases {
    private static let map: [String: String] = [
        "workspace.livingSky":  "workspace.appearance",
        "workspace.appIcon":    "workspace.appearance",
        "workspace.sound":      "workspace.soundAndVoice",
        "workspace.shortcuts":  "workspace.keyboard",
        "workspace.mcp":        "intelligence.tools",
        "workspace.lsp":        "intelligence.tools",
        "workspace.skills":     "intelligence.skills",
        "workspace.memory":     "intelligence.memory",
        "assistant.models":     "intelligence.model",
        "assistant.access":     "intelligence.permissions",
        "assistant.data":       "intelligence.privacy",
        "assistant.web":        "intelligence.tools",
        "assistant.voice":      "workspace.soundAndVoice",
        "assistant.appearance": "workspace.appearance"
    ]

    static func resolve(_ path: SettingsPath) -> SettingsPath {
        guard let target = map[path.rawValue],
              let resolved = SettingsPath(rawValue: target) else { return path }
        return resolved
    }

    static var allTargets: [SettingsPath] {
        map.values.compactMap { SettingsPath(rawValue: $0) }
    }
}
