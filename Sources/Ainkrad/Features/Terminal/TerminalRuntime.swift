import AinkradAppKit

/// Bridges Terminal's static `AinkradApp` entry points to a single shared,
/// observable `TerminalSettingsStore` per host. `makeRootView(host:)` and
/// `makeSettingsView(host:)` receive the same host instance, so every Terminal
/// pane and the settings pane share one store — a settings edit restyles all
/// running terminals live. Keyed by host object identity (the host is always a
/// reference type — `HostServicesImpl`).
@MainActor
enum TerminalRuntime {
    private static var stores: [ObjectIdentifier: TerminalSettingsStore] = [:]

    static func settingsStore(for host: HostServices) -> TerminalSettingsStore {
        let key = ObjectIdentifier(host as AnyObject)
        if let existing = stores[key] { return existing }
        let store = TerminalSettingsStore(documents: host.documents)
        stores[key] = store
        return store
    }
}
