import Foundation
import Observation

struct AgentConfigDocument: PersistableDocument {
    static let documentID = "agent-config"

    var activeConnectionID: UUID?
    var model: String = "claude-opus-4-8"
    var effort: String = "xhigh"

    init(activeConnectionID: UUID? = nil, model: String = "claude-opus-4-8", effort: String = "xhigh") {
        self.activeConnectionID = activeConnectionID
        self.model = model
        self.effort = effort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeConnectionID = try c.decodeIfPresent(UUID.self, forKey: .activeConnectionID)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "claude-opus-4-8"
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? "xhigh"
        // Legacy `provider` field (if present) is ignored — the active
        // connection is resolved from the connection list at runtime.
    }

    enum CodingKeys: String, CodingKey { case activeConnectionID, model, effort }
}

@MainActor
@Observable
final class AgentConfigStore {
    private(set) var current: AgentModelConfig
    private(set) var activeConnectionID: UUID?
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let document = persistence.load(AgentConfigDocument.self) ?? AgentConfigDocument()
        self.activeConnectionID = document.activeConnectionID
        self.current = AgentModelConfig(model: document.model, effort: document.effort)
    }

    func setActiveConnectionID(_ id: UUID?) { activeConnectionID = id; save() }
    func setModel(_ model: String) { current.model = model; save() }
    func setEffort(_ effort: String) { current.effort = effort; save() }

    private func save() {
        persistence.save(AgentConfigDocument(
            activeConnectionID: activeConnectionID, model: current.model, effort: current.effort))
    }
}
