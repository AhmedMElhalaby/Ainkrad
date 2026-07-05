import Testing
import Foundation
@testable import Ainkrad

@Suite("ThemeManager")
final class ThemeManagerTests {
    let store = InMemoryPersistenceStore()

    @MainActor
    private func makeManager() -> ThemeManager {
        ThemeManager(persistence: store)
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
        let manager = ThemeManager(persistence: store)
        manager.setTheme(.cyberPurple)

        let reloaded = ThemeManager(persistence: store)
        #expect(reloaded.currentTheme == .cyberPurple)
    }
}
