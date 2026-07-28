// Sources/Ainkrad/Core/AgentKit/MCP/AppServerActivator.swift
import Foundation
import AinkradAppKit
import AinkradHostRuntime

/// Why an app's MCP server could not be reached. Distinct cases so the failure
/// text the model sees names an actionable cause instead of "something failed".
enum AppDispatchFailure: Error, Equatable {
    /// No app with that id has an MCP server (not installed, or doesn't conform).
    case notInstalled(String)
    /// Registered but switched off by the user.
    case disabled(String)
    /// Launch was requested but the app never came up inside the timeout.
    case launchTimedOut(String)
}

/// Owns the app-side MCP servers and the lifecycle around reaching them.
///
/// An app's server object can exist while the app is closed, but its handlers
/// generally hold a bridge that is nil with no live shell (see GitMage's
/// `contextBridge`), so a call to a closed app must open it FIRST. That is the
/// whole reason this type exists — `InProcessTransport` stays a dumb pipe.
///
/// Collaborators arrive as closures rather than as `PluginLaunchHub` + the app
/// registry so this is testable without a host bootstrap; `AppEnvironment`
/// supplies hub-backed closures.
@MainActor
final class AppServerActivator {
    private let servers: [String: MCPAppServer]
    private let isAppOpen: (String) -> Bool
    private let requestOpen: (String) -> Void
    private let availability: (String) -> PluginLaunchHub.Availability
    private let launchTimeout: Duration
    private let onLaunch: ((String) -> Void)?
    /// How often to re-check `isAppOpen` while waiting for a launch.
    private let pollInterval: Duration = .milliseconds(50)

    init(servers: [String: MCPAppServer],
         isAppOpen: @escaping (String) -> Bool,
         requestOpen: @escaping (String) -> Void,
         availability: @escaping (String) -> PluginLaunchHub.Availability,
         launchTimeout: Duration = .seconds(5),
         onLaunch: ((String) -> Void)? = nil) {
        self.servers = servers
        self.isAppOpen = isAppOpen
        self.requestOpen = requestOpen
        self.availability = availability
        self.launchTimeout = launchTimeout
        self.onLaunch = onLaunch
    }

    /// True when this app publishes an MCP server at all.
    func hasServer(appID: String) -> Bool { servers[appID] != nil }

    /// Sends one JSON-RPC message to the app's server, opening the app first if
    /// it isn't already open. Returns the raw reply, or an empty string when the
    /// message was a notification.
    func dispatch(appID: String, message: String) async throws -> String {
        guard let server = servers[appID] else { throw AppDispatchFailure.notInstalled(appID) }

        if !isAppOpen(appID) {
            switch availability(appID) {
            case .unknown: throw AppDispatchFailure.notInstalled(appID)
            case .disabled: throw AppDispatchFailure.disabled(appID)
            case .available: break
            }
            requestOpen(appID)
            onLaunch?(appID)
            try await waitUntilOpen(appID)
        }
        return await server.handle(message)
    }

    /// Bounded wait — never an unbounded spin. Uses a deadline rather than a
    /// fixed iteration count so the poll interval can change without silently
    /// changing the timeout.
    private func waitUntilOpen(_ appID: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: launchTimeout)
        while ContinuousClock.now < deadline {
            if isAppOpen(appID) { return }
            try? await Task.sleep(for: pollInterval)
        }
        guard isAppOpen(appID) else { throw AppDispatchFailure.launchTimedOut(appID) }
    }
}
