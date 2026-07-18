import Foundation

/// The three always-loaded markdown memory files (global scope).
enum MemoryFile: String, CaseIterable {
    case user = "USER.md"
    case memory = "MEMORY.md"
    case agents = "AGENTS.md"
}
