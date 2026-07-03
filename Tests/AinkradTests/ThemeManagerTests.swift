import Testing
import Foundation
@testable import Ainkrad

@MainActor
private final class SpyDockIconUpdater: DockIconUpdating {
    private(set) var updatedIcons: [AppIcon] = []
    func updateDockIcon(_ icon: AppIcon) {
        updatedIcons.append(icon)
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

    @Test("with Auto icon, setTheme swaps the Dock icon to match the new theme")
    @MainActor
    func setThemeTriggersDockIconUpdate() {
        let spy = SpyDockIconUpdater()
        let manager = makeManager(dockIconUpdater: spy)
        manager.setTheme(.cyberPurple)
        #expect(spy.updatedIcons == [.purple])
    }

    @Test("appIcon defaults to Auto with no prior saved settings")
    @MainActor
    func appIconDefaultsToAuto() {
        #expect(makeManager().appIcon == .auto)
    }

    @Test("setAppIcon updates state, persists, and swaps the Dock icon")
    @MainActor
    func setAppIconAppliesAndPersists() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let spy = SpyDockIconUpdater()
        let manager = ThemeManager(settingsStore: store, dockIconUpdater: spy)

        manager.setAppIcon(.purple)

        #expect(manager.appIcon == .purple)
        #expect(spy.updatedIcons == [.purple])
        let reloaded = ThemeManager(settingsStore: store, dockIconUpdater: SpyDockIconUpdater())
        #expect(reloaded.appIcon == .purple)
    }

    @Test("an explicit app icon is NOT overridden by a later theme change")
    @MainActor
    func explicitIconSurvivesThemeChange() {
        let spy = SpyDockIconUpdater()
        let manager = makeManager(dockIconUpdater: spy)

        manager.setAppIcon(.purple)   // -> [.purple]
        manager.setTheme(.neonBlue)   // Auto would swap to .blue; explicit must not

        #expect(spy.updatedIcons == [.purple])
    }
}
