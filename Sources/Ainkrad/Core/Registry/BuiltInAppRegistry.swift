/// Single source of truth for which Built-in Apps exist and are enabled.
/// Feeds the App Launcher's "Apps" section and determines which Block types
/// can be instantiated — see Window & Tile Management Architecture.md.
final class BuiltInAppRegistry {
    private static let enabledStateKey = "registry-enabled-state"

    private let registeredApps: [BuiltInApp.Type]
    private let settingsStore: SettingsStore
    private var enabledOverrides: [String: Bool]

    init(apps: [BuiltInApp.Type], settingsStore: SettingsStore) {
        self.registeredApps = apps
        self.settingsStore = settingsStore
        self.enabledOverrides = settingsStore.get([String: Bool].self, forKey: Self.enabledStateKey) ?? [:]
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
        settingsStore.set(enabledOverrides, forKey: Self.enabledStateKey)
    }
}
