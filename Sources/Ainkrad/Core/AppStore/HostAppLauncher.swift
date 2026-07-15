import AinkradAppKit

/// Per-app `PluginAppLauncher` handed to one plugin's HostServices. Forwards to
/// the shared hub, tagged with this app's id (mirrors `HostContextRegistry`).
@MainActor
struct HostAppLauncher: PluginAppLauncher {
    let appID: String
    unowned let hub: PluginLaunchHub

    func open(appID: String, payload: String?) {
        hub.enqueue(target: appID, payload: payload)
        hub.requestOpen(appID)
    }
    func takePendingLaunch() -> String? { hub.takePending(for: appID) }
}
