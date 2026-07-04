/// Single source of truth for which Built-in Apps exist and are enabled.
/// Feeds the App Launcher's "Apps" section and determines which Block types
/// can be instantiated — see Window & Tile Management Architecture.md.
final class BuiltInAppRegistry {
    private let registeredApps: [BuiltInApp.Type]
    private let persistence: PersistenceStore
    private var enabledOverrides: [String: Bool]

    init(apps: [BuiltInApp.Type], persistence: PersistenceStore) {
        self.registeredApps = apps
        self.persistence = persistence
        self.enabledOverrides = persistence.load(RegistryStateDocument.self)?.enabled ?? [:]
    }

    var allApps: [BuiltInApp.Type] { registeredApps }

    var enabledApps: [BuiltInApp.Type] {
        registeredApps.filter { isEnabled($0.id) }
    }

    func isEnabled(_ id: String) -> Bool {
        if let override = enabledOverrides[id] {
            return override
        }
        return registeredApps.first(where: { $0.id == id })?.isEnabledByDefault ?? false
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        enabledOverrides[id] = enabled
        persistence.save(RegistryStateDocument(enabled: enabledOverrides))
        Log.registry.info("Built-in App \(id, privacy: .public) \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
}
