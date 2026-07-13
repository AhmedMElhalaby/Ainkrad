import Foundation
import AinkradAppKit

/// The per-app `PluginContextRegistry` handed to one plugin's HostServices.
/// Forwards to the shared host hub, tagging registrations with this app's id.
@MainActor
struct HostContextRegistry: PluginContextRegistry {
    let appID: String
    unowned let hub: AgentContextRegistryHub

    func register(_ source: @escaping @MainActor () -> AgentContextSnapshot?) -> PluginContextToken {
        hub.register(appID: appID, source)
    }
    func remove(_ token: PluginContextToken) { hub.remove(token) }
}
