// Sources/Ainkrad/Core/AgentKit/MCP/MCPArgumentRisk.swift
import Foundation
import AinkradHostRuntime

/// Generalizes the host's old git-only `optionLookingValue` check off git so
/// the same argument-
/// injection defense applies to every MCP tool, including third-party
/// servers. MCP's `destructiveHint` is a static per-tool boolean and cannot
/// express per-call irreversibility, so this rule walks the actual call
/// arguments: an option-looking value anywhere in the payload is dangerous
/// for any tool that reaches a CLI (`--upload-pack=<cmd>`, `--exec=<cmd>`,
/// `-c core.pager=<cmd>`, the `ext::` transport helper, …), regardless of
/// what the server claims about itself.
enum MCPArgumentRisk {
    /// True when any value reachable from `input` looks like a command-line
    /// option rather than plain data. Unlike the old git-only check, there is no
    /// `repoPath`/`args` shape to special-case here — a generic MCP payload
    /// is walked in full, top level included.
    static func hasOptionLookingValue(_ input: JSONValue) -> Bool {
        firstOptionLooking(input) != nil
    }

    /// Recurses into arrays and objects — an injected option nested one
    /// level down (`{"paths": ["--exec=…"]}`) is exactly as dangerous as a
    /// top-level one. Object walks are sorted-key so the result is
    /// deterministic across runs rather than flapping with dictionary order.
    private static func firstOptionLooking(_ value: JSONValue) -> String? {
        switch value {
        case .string(let s):
            if s.hasPrefix("-") { return s }
            // `ext::sh -c …` is git's own transport-helper escape hatch: it
            // runs an arbitrary command, and it needs no leading dash to do
            // it. Kept here even off-git, since a generic CLI-backed MCP
            // server can shell out to git (or something like it) too.
            if s.lowercased().hasPrefix("ext::") { return s }
            return nil
        case .array(let items):
            for item in items { if let found = firstOptionLooking(item) { return found } }
            return nil
        case .object(let dict):
            for key in dict.keys.sorted() {
                if let v = dict[key], let found = firstOptionLooking(v) { return found }
            }
            return nil
        default:
            return nil
        }
    }
}
