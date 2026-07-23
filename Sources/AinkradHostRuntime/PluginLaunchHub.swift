import Foundation

/// Host-owned mailbox for app→app launches. Holds at most one pending payload
/// per target appID (a newer open for the same target replaces an unconsumed
/// one). `requestOpen` asks the host to open the target's pane. Mirrors the
/// AgentContext/Action hub shape (shared, `@MainActor`).
@MainActor
public final class PluginLaunchHub {
    private var pending: [String: String] = [:]
    private var openHandler: ((String) -> Void)?

    public init() {}

    /// Wired once in bootstrap to open a pane via the WorkspaceManager.
    public func setOpenHandler(_ handler: @escaping (String) -> Void) { openHandler = handler }

    public func enqueue(target appID: String, payload: String?) { pending[appID] = payload }

    public func requestOpen(_ appID: String) { openHandler?(appID) }

    public func takePending(for appID: String) -> String? {
        defer { pending[appID] = nil }
        return pending[appID]
    }
}
