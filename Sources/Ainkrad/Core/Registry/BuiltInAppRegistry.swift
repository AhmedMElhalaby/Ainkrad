/// Single source of truth for which apps exist and are enabled. Hybrid: apps
/// are installed once after `AppEnvironment` exists, mixing compiled-in apps
/// with dynamically-loaded plugin bundles.
@MainActor
final class BuiltInAppRegistry {
    private var registeredApps: [RegisteredApp] = []
    private let persistence: PersistenceStore
    private var enabledOverrides: [String: Bool]
    private(set) var loadFailures: [PluginLoadFailure] = []

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.enabledOverrides = persistence.load(RegistryStateDocument.self)?.enabled ?? [:]
    }

    /// Installs the resolved app set. Built-in apps win id conflicts with
    /// plugins. Called once during bootstrap after the environment exists.
    func install(builtIn: [RegisteredApp], loaded: [RegisteredApp] = [], failures: [PluginLoadFailure] = []) {
        loadFailures = failures
        var byID: [String: RegisteredApp] = [:]
        var order: [String] = []
        for app in builtIn where byID[app.id] == nil { byID[app.id] = app; order.append(app.id) }
        for app in loaded {
            if byID[app.id] != nil {
                Log.registry.error("Plugin id conflict \(app.id, privacy: .public) — built-in wins, plugin skipped")
                continue
            }
            byID[app.id] = app
            order.append(app.id)
        }
        registeredApps = order.compactMap { byID[$0] }
    }

    var allApps: [RegisteredApp] { registeredApps }

    var enabledApps: [RegisteredApp] { registeredApps.filter { isEnabled($0.id) } }

    func isEnabled(_ id: String) -> Bool {
        if let override = enabledOverrides[id] { return override }
        return registeredApps.first(where: { $0.id == id })?.isEnabledByDefault ?? false
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        enabledOverrides[id] = enabled
        persistence.save(RegistryStateDocument(enabled: enabledOverrides))
        Log.registry.info("App \(id, privacy: .public) \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
}
