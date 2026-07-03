import Testing
import Foundation
@testable import Ainkrad

@Suite("TerminalSettings")
final class TerminalSettingsTests {
    let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { self.defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }

    @Test("defaults to nil shell and working directory with no prior write")
    func defaultsToNilFields() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let loaded = store.get(TerminalSettings.self, forKey: TerminalSettings.storeKey) ?? TerminalSettings()
        #expect(loaded.defaultShell == nil)
        #expect(loaded.defaultWorkingDirectory == nil)
    }

    @Test("a written selection round-trips through SettingsStore")
    func writtenSelectionRoundTrips() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = TerminalSettings()
        settings.defaultShell = "/bin/bash"
        settings.defaultWorkingDirectory = URL(fileURLWithPath: "/tmp")
        store.set(settings, forKey: TerminalSettings.storeKey)

        let loaded = store.get(TerminalSettings.self, forKey: TerminalSettings.storeKey)

        #expect(loaded?.defaultShell == "/bin/bash")
        #expect(loaded?.defaultWorkingDirectory == URL(fileURLWithPath: "/tmp"))
    }

    @Test("appearance fields default to Match Theme and nil font")
    func appearanceDefaults() {
        let settings = TerminalSettings()
        #expect(settings.colorSchemeID == TerminalColorScheme.matchThemeID)
        #expect(settings.fontFamily == nil)
        #expect(settings.fontSize == nil)
    }

    @Test("appearance fields round-trip through SettingsStore")
    func appearanceRoundTrips() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = TerminalSettings()
        settings.colorSchemeID = "dracula"
        settings.fontFamily = "Menlo"
        settings.fontSize = 15
        store.set(settings, forKey: TerminalSettings.storeKey)

        let loaded = store.get(TerminalSettings.self, forKey: TerminalSettings.storeKey)
        #expect(loaded?.colorSchemeID == "dracula")
        #expect(loaded?.fontFamily == "Menlo")
        #expect(loaded?.fontSize == 15)
    }

    @Test("a legacy payload without appearance fields decodes to defaults")
    func legacyPayloadDecodesToDefaults() throws {
        let legacy = Data(#"{"defaultShell":"/bin/zsh"}"#.utf8)
        let decoded = try JSONDecoder().decode(TerminalSettings.self, from: legacy)
        #expect(decoded.defaultShell == "/bin/zsh")
        #expect(decoded.colorSchemeID == TerminalColorScheme.matchThemeID)
        #expect(decoded.fontFamily == nil)
    }
}

@Suite("Terminal appearance resolution")
struct TerminalAppearanceResolverTests {

    @Test("Match Theme derives the terminal colors from the active app theme")
    func matchThemeFollowsTheme() {
        let blue = TerminalAppearanceResolver.resolve(
            settings: TerminalSettings(),
            theme: .neonBlue
        )
        #expect(blue.background == "0A0E17")
        #expect(blue.foreground == "E2E8F0")

        let purple = TerminalAppearanceResolver.resolve(
            settings: TerminalSettings(),
            theme: .cyberPurple
        )
        #expect(purple.background == "080814")
    }

    @Test("A named scheme uses its own colors regardless of theme")
    func namedSchemeIgnoresTheme() {
        var settings = TerminalSettings()
        settings.colorSchemeID = "dracula"
        let a = TerminalAppearanceResolver.resolve(settings: settings, theme: .neonBlue)
        let b = TerminalAppearanceResolver.resolve(settings: settings, theme: .cyberPurple)
        #expect(a.background == b.background)
        #expect(a.background == "282A36")   // Dracula background
    }

    @Test("Every resolved appearance carries a full 16-color ANSI palette")
    func ansiPaletteHasSixteen() {
        #expect(TerminalAppearanceResolver.resolve(settings: TerminalSettings(), theme: .neonBlue).ansi.count == 16)
        var dracula = TerminalSettings()
        dracula.colorSchemeID = "dracula"
        #expect(TerminalAppearanceResolver.resolve(settings: dracula, theme: .neonBlue).ansi.count == 16)
    }

    @Test("Font falls back to defaults when unset, and passes explicit values through")
    func fontResolution() {
        let dflt = TerminalAppearanceResolver.resolve(settings: TerminalSettings(), theme: .neonBlue)
        #expect(!dflt.fontFamily.isEmpty)
        #expect(dflt.fontSize == 13)

        var custom = TerminalSettings()
        custom.fontFamily = "Menlo"
        custom.fontSize = 16
        let resolved = TerminalAppearanceResolver.resolve(settings: custom, theme: .neonBlue)
        #expect(resolved.fontFamily == "Menlo")
        #expect(resolved.fontSize == 16)
    }

    @Test("An unknown scheme id falls back to Match Theme")
    func unknownSchemeFallsBack() {
        #expect(TerminalColorScheme.scheme(id: "does-not-exist").id == TerminalColorScheme.matchThemeID)
    }
}
