import Foundation
import AinkradAppKit

/// The per-app `AgentActionProvider` handed to one plugin's HostServices.
/// Forwards to the shared host hub, tagging registrations with this app's id.
@MainActor
struct HostActionRegistry: AgentActionProvider {
    let appID: String
    unowned let hub: AgentActionRegistryHub

    func register(actionID: String,
                  handler: @escaping @MainActor (String) async -> AgentActionResult) -> AgentActionToken {
        hub.register(appID: appID, actionID: actionID, handler: handler)
    }
    func remove(_ token: AgentActionToken) { hub.remove(token) }
}
