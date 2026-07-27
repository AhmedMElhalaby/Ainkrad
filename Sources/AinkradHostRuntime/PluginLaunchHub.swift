import Foundation

/// Host-owned mailbox for app→app launches. Holds at most one pending payload
/// per target appID (a newer open for the same target replaces an unconsumed
/// one). `requestOpen` asks the host to open the target's pane. Mirrors the
/// AgentContext/Action hub shape (shared, `@MainActor`).
@MainActor
public final class PluginLaunchHub {
    private var pending: [String: String] = [:]
    private var openHandler: ((String) -> Void)?
    private var availabilityProvider: ((String) -> Availability)?

    /// Whether a target app can be opened right now.
    public enum Availability: Equatable, Sendable {
        case available
        /// Registered but switched off by the user.
        case disabled
        /// No app with that id — not installed, or failed to load.
        case unknown
    }

    public init() {}

    /// Wired once in bootstrap to open a pane via the WorkspaceManager.
    public func setOpenHandler(_ handler: @escaping (String) -> Void) { openHandler = handler }

    /// Wired once in bootstrap; lets a launch report *why* it didn't happen
    /// instead of silently doing nothing. Absent (tests, early bootstrap) means
    /// "assume available", preserving the pre-generation-8 behaviour exactly.
    public func setAvailabilityProvider(_ provider: @escaping (String) -> Availability) {
        availabilityProvider = provider
    }

    public func availability(of appID: String) -> Availability {
        availabilityProvider?(appID) ?? .available
    }

    public func enqueue(target appID: String, payload: String?) { pending[appID] = payload }

    public func requestOpen(_ appID: String) { openHandler?(appID) }

    public func takePending(for appID: String) -> String? {
        defer { pending[appID] = nil }
        return pending[appID]
    }
}
