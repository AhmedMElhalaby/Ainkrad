import Foundation

/// Static, bundled metadata about one model (or model family) that the Model
/// Router uses to order and filter candidates. `matchPrefixes` lets a single
/// descriptor cover a whole family (e.g. `"claude-haiku"` matches dated/suffixed
/// variants like `"claude-haiku-4-8-20260101"`).
struct ModelDescriptor: Codable, Equatable, Sendable {
    let id: String
    let tier: ModelTier
    let contextWindow: Int
    let capabilities: ModelCapability
    let matchPrefixes: [String]

    init(
        id: String,
        tier: ModelTier,
        contextWindow: Int,
        capabilities: ModelCapability,
        matchPrefixes: [String] = []
    ) {
        self.id = id
        self.tier = tier
        self.contextWindow = contextWindow
        self.capabilities = capabilities
        self.matchPrefixes = matchPrefixes
    }
}
