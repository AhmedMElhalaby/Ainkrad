import Foundation
import Observation

/// Persisted document backing `AgentConfigStore`. A missing/legacy field
/// falls back to the documented default — same tolerant-decode idiom as
/// `GlobalSettings`.
struct AgentConfigDocument: PersistableDocument {
    static let documentID = "agent-config"

    var provider: AgentProvider = .claude
    var model: String = "claude-opus-4-8"
    var effort: String = "xhigh"

    init(provider: AgentProvider = .claude, model: String = "claude-opus-4-8", effort: String = "xhigh") {
        self.provider = provider
        self.model = model
        self.effort = effort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(AgentProvider.self, forKey: .provider) ?? .claude
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "claude-opus-4-8"
        effort = try container.decodeIfPresent(String.self, forKey: .effort) ?? "xhigh"
    }
}

/// Owns the default agent provider/model/effort (Settings → Assistant →
/// Model). Loads from `AgentConfigDocument` and persists changes — same
/// load/mutate/save pattern as `GeneralSettingsStore`.
///
/// Model choice on provider switch: rather than tracking a separate stored
/// model per provider, switching `provider` resets `model` to that
/// provider's own default (`claude-opus-4-8` / `gpt-5`). This keeps the
/// document minimal and avoids a stale model string surviving a provider
/// switch (e.g. an OpenAI model id lingering after switching to Claude).
@MainActor
@Observable
final class AgentConfigStore {
    private(set) var current: AgentModelConfig
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let document = persistence.load(AgentConfigDocument.self) ?? AgentConfigDocument()
        self.current = AgentModelConfig(provider: document.provider, model: document.model, effort: document.effort)
    }

    func setProvider(_ provider: AgentProvider) {
        current = AgentModelConfig(provider: provider, model: Self.defaultModel(for: provider), effort: current.effort)
        save()
    }

    func setModel(_ model: String) {
        current.model = model
        save()
    }

    func setEffort(_ effort: String) {
        current.effort = effort
        save()
    }

    private func save() {
        persistence.save(AgentConfigDocument(provider: current.provider, model: current.model, effort: current.effort))
    }

    private static func defaultModel(for provider: AgentProvider) -> String {
        switch provider {
        case .claude: return "claude-opus-4-8"
        case .openai: return "gpt-5"
        }
    }
}
