import Testing
import Foundation
@testable import Ainkrad

@Suite("GlobalSettings")
final class GlobalSettingsTests {
    @Test("defaults to Neon Blue with no prior write")
    func defaultsToNeonBlue() {
        let store = InMemoryPersistenceStore()
        let loaded = store.load(GlobalSettings.self) ?? GlobalSettings()
        #expect(loaded.theme == .neonBlue)
    }

    @Test("a written Cyber Purple selection round-trips through the persistence store")
    func cyberPurpleRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.theme = .cyberPurple
        store.save(settings)
        #expect(store.load(GlobalSettings.self)?.theme == .cyberPurple)
    }

    @Test("a legacy payload with an extra unknown field still decodes the theme")
    func legacyPayloadWithExtraFieldDecodes() throws {
        let legacy = Data(#"{"theme":"cyberPurple","appIcon":"purple"}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.theme == .cyberPurple)
    }

    @Test("a payload without theme decodes to the Neon Blue default")
    func missingThemeDecodesToDefault() throws {
        let legacy = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.theme == .neonBlue)
    }

    @Test("defaults to medium/exo2/no accent override with no prior write")
    func typographyDefaults() {
        let settings = GlobalSettings()
        #expect(settings.uiFontScale == .medium)
        #expect(settings.uiFontFamily == .exo2)
        #expect(settings.accentColorHex == nil)
    }

    @Test("a written typography selection round-trips through the persistence store")
    func typographyRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.uiFontScale = .large
        settings.uiFontFamily = .jetBrainsMono
        settings.accentColorHex = "FF00AA"
        store.save(settings)

        let reloaded = store.load(GlobalSettings.self)
        #expect(reloaded?.uiFontScale == .large)
        #expect(reloaded?.uiFontFamily == .jetBrainsMono)
        #expect(reloaded?.accentColorHex == "FF00AA")
    }

    @Test("a legacy payload without the new typography keys decodes to defaults and preserves existing fields")
    func legacyPayloadWithoutTypographyKeysDecodesToDefaults() throws {
        let legacy = Data(#"{"theme":"cyberPurple","confirmBeforeQuit":false}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.theme == .cyberPurple)
        #expect(decoded.confirmBeforeQuit == false)
        #expect(decoded.uiFontScale == .medium)
        #expect(decoded.uiFontFamily == .exo2)
        #expect(decoded.accentColorHex == nil)
    }

    @Test("reduce-motion defaults to off (motion on) with no prior write")
    func reduceMotionDefaultsOff() {
        #expect(GlobalSettings().uiReduceMotion == false)
    }

    @MainActor
    @Test("setUiReduceMotion updates the store and persists across a fresh load")
    func reduceMotionSetterRoundTrips() {
        let persistence = InMemoryPersistenceStore()
        let store = GeneralSettingsStore(persistence: persistence)
        #expect(store.uiReduceMotion == false)

        store.setUiReduceMotion(true)
        #expect(store.uiReduceMotion == true)
        // Persisted: a store rebuilt on the same backing sees the new value.
        #expect(GeneralSettingsStore(persistence: persistence).uiReduceMotion == true)
    }

    @MainActor
    @Test("first launch defaults to motion on and never adopts the macOS Reduce Motion flag")
    func reduceMotionNeverSeedsFromSystem() {
        let persistence = InMemoryPersistenceStore()
        // No prior document → motion is ON regardless of the OS setting; the app
        // never reads the system Reduce Motion flag. The in-app toggle is the
        // sole source of truth.
        #expect(GeneralSettingsStore(persistence: persistence).uiReduceMotion == false)
    }
}
