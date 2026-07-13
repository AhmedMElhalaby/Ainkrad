import Foundation
import Observation

struct AgentPermissionDocument: PersistableDocument {
    static let documentID = "agent-permissions"

    var defaultMode: AgentPermissionMode = .ask
    var allowlist: [String] = []
    var perWorkspace: [String: AgentPermissionMode] = [:]
    /// Global (not per-workspace) toggle: when true, `.read` tools require approval in
    /// `Ask`/`Auto-approve` modes too (unless explicitly allowlisted).
    var gateReads: Bool = true

    init(defaultMode: AgentPermissionMode = .ask,
         allowlist: [String] = [],
         perWorkspace: [String: AgentPermissionMode] = [:],
         gateReads: Bool = true) {
        self.defaultMode = defaultMode
        self.allowlist = allowlist
        self.perWorkspace = perWorkspace
        self.gateReads = gateReads
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultMode = try c.decodeIfPresent(AgentPermissionMode.self, forKey: .defaultMode) ?? .ask
        allowlist = try c.decodeIfPresent([String].self, forKey: .allowlist) ?? []
        perWorkspace = try c.decodeIfPresent([String: AgentPermissionMode].self, forKey: .perWorkspace) ?? [:]
        gateReads = try c.decodeIfPresent(Bool.self, forKey: .gateReads) ?? true
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

    var gateReads: Bool { document.gateReads }

    func setMode(_ mode: AgentPermissionMode) {
        document.perWorkspace[currentWorkspaceID().uuidString] = mode
        persistence.save(document)
    }

    func setGateReads(_ value: Bool) {
        document.gateReads = value
        persistence.save(document)
    }
}
