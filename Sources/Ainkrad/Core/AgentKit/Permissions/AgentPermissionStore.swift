import Foundation
import Observation

struct AgentPermissionDocument: PersistableDocument {
    static let documentID = "agent-permissions"

    var defaultMode: AgentPermissionMode = .ask
    var allowlist: [String] = []
    var perWorkspace: [String: AgentPermissionMode] = [:]

    init(defaultMode: AgentPermissionMode = .ask,
         allowlist: [String] = [],
         perWorkspace: [String: AgentPermissionMode] = [:]) {
        self.defaultMode = defaultMode
        self.allowlist = allowlist
        self.perWorkspace = perWorkspace
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultMode = try c.decodeIfPresent(AgentPermissionMode.self, forKey: .defaultMode) ?? .ask
        allowlist = try c.decodeIfPresent([String].self, forKey: .allowlist) ?? []
        perWorkspace = try c.decodeIfPresent([String: AgentPermissionMode].self, forKey: .perWorkspace) ?? [:]
    }
}

/// Owns the per-workspace permission mode + the auto-approve allowlist.
/// The active workspace id is read lazily via the injected closure so the store
/// stays decoupled from `WorkspaceManager` (and trivially testable).
@MainActor
@Observable
final class AgentPermissionStore {
    private var document: AgentPermissionDocument
    private let persistence: PersistenceStore
    private let currentWorkspaceID: @MainActor () -> UUID

    init(persistence: PersistenceStore, currentWorkspaceID: @escaping @MainActor () -> UUID) {
        self.persistence = persistence
        self.currentWorkspaceID = currentWorkspaceID
        self.document = persistence.load(AgentPermissionDocument.self) ?? AgentPermissionDocument()
    }

    var mode: AgentPermissionMode {
        document.perWorkspace[currentWorkspaceID().uuidString] ?? document.defaultMode
    }

    var allowlist: Set<String> { Set(document.allowlist) }

    func setMode(_ mode: AgentPermissionMode) {
        document.perWorkspace[currentWorkspaceID().uuidString] = mode
        persistence.save(document)
    }
}
