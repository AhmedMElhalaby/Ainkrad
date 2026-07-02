import Testing
import Foundation
@testable import Ainkrad

@MainActor
private final class SpyDockIconUpdater: DockIconUpdating {
    private(set) var updatedThemes: [Theme] = []
    func updateDockIcon(for theme: Theme) {
        updatedThemes.append(theme)
    }
}

@Suite("ThemeManager")
final class ThemeManagerTests {
    let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { self.defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }

    @MainActor
    private func makeManager(dockIconUpdater: SpyDockIconUpdater = SpyDockIconUpdater()) -> ThemeManager {
        ThemeManager(
            settingsStore: UserDefaultsSettingsStore(defaults: defaults),
            dockIconUpdater: dockIconUpdater
        )
    }

    @Test("defaults to Neon Blue with no prior saved settings")
    @MainActor
    func defaultsToNeonBlue() {
        let manager = makeManager()
        #expect(manager.currentTheme == .neonBlue)
        #expect(manager.tokens == DesignTokens.neonBlue)
    }

    @Test("setTheme updates currentTheme and tokens immediately")
    @MainActor
    func setThemeUpdatesState() {
        let manager = makeManager()
        manager.setTheme(.cyberPurple)
        #expect(manager.currentTheme == .cyberPurple)
        #expect(manager.tokens == DesignTokens.cyberPurple)
    }

    @Test("setTheme persists the selection through SettingsStore")
    @MainActor
    func setThemePersists() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let manager = ThemeManager(settingsStore: store, dockIconUpdater: SpyDockIconUpdater())
        manager.setTheme(.cyberPurple)

        let reloaded = ThemeManager(settingsStore: store, dockIconUpdater: SpyDockIconUpdater())
        #expect(reloaded.currentTheme == .cyberPurple)
    }

    @Test("setTheme triggers the Dock icon update side effect with the new theme")
    @MainActor
    func setThemeTriggersDockIconUpdate() {
        let spy = SpyDockIconUpdater()
        let manager = makeManager(dockIconUpdater: spy)
        manager.setTheme(.cyberPurple)
        #expect(spy.updatedThemes == [.cyberPurple])
    }
}
