import Foundation

/// The v0.16.0 app rename table and the two pure transforms every migration
/// shares. One place, so a fifth rename is a one-line change here.
///
/// Kept in `AinkradHostRuntime` rather than the app target because
/// `AppAppearanceDocument` lives here and must migrate too.
public enum AppIDRenames {
    /// Retired app id → its replacement. See the 2026-08-02 naming design.
    public static let map: [String: String] = [
        "files": "hoard",
        "assistant": "sage",
        "canvas": "scry",
        "terminal": "rune",
    ]

    /// Re-keys an appID-keyed JSON object. A value already stored under the NEW
    /// id wins — a user who somehow has both keeps the current one rather than
    /// having it overwritten by stale state.
    public static func rekeyed(_ object: [String: JSONValue]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (key, value) in object where map[key] == nil { out[key] = value }
        for (old, new) in map {
            guard let value = object[old] else { continue }
            if object[new] == nil { out[new] = value }
        }
        return out
    }

    /// Rewrites a tool name or glob whose prefix is a retired app id
    /// (`files_navigate` → `hoard_navigate`). Matching is on the exact
    /// `<id>_` prefix, so the host's own `run_terminal` is untouched.
    public static func renamedToolName(_ name: String) -> String {
        for (old, new) in map where name.hasPrefix("\(old)_") {
            return new + name.dropFirst(old.count)
        }
        return name
    }
}
