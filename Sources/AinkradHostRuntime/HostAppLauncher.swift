import AinkradAppKit

/// Per-app `PluginAppLauncher` handed to one plugin's HostServices. Forwards to
/// the shared hub, tagged with this app's id (mirrors `HostContextRegistry`).
@MainActor
public struct HostAppLauncher: PluginAppLauncher {
    let appID: String
    unowned let hub: PluginLaunchHub

    public init(appID: String, hub: PluginLaunchHub) {
        self.appID = appID
        self.hub = hub
    }

    public func open(appID: String, payload: String?) {
        hub.enqueue(target: appID, payload: payload)
        hub.requestOpen(appID)
    }
    public func takePendingLaunch() -> String? { hub.takePending(for: appID) }
}
