import Testing
import Foundation
@testable import Ainkrad

@Suite("TerminalSettings")
final class TerminalSettingsTests {
    @Test("defaults to nil shell and working directory with no prior write")
    func defaultsToNilFields() {
        let store = InMemoryPersistenceStore()
        let loaded = store.load(TerminalSettings.self) ?? TerminalSettings()
        #expect(loaded.defaultShell == nil)
        #expect(loaded.defaultWorkingDirectory == nil)
    }

    @Test("a written selection round-trips through the persistence store")
    func writtenSelectionRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = TerminalSettings()
        settings.defaultShell = "/bin/bash"
        settings.defaultWorkingDirectory = URL(fileURLWithPath: "/tmp")
        store.save(settings)

        let loaded = store.load(TerminalSettings.self)
        #expect(loaded?.defaultShell == "/bin/bash")
        #expect(loaded?.defaultWorkingDirectory == URL(fileURLWithPath: "/tmp"))
    }

    @Test("appearance fields default to Match Theme and nil font")
    func appearanceDefaults() {
        let settings = TerminalSettings()
        #expect(settings.colorSchemeID == TerminalColorScheme.matchThemeID)
        #expect(settings.fontFamily == nil)
        #expect(settings.fontSize == nil)
        #expect(settings.cursorShape == .block)
        #expect(settings.cursorBlink == true)
        #expect(settings.optionAsMeta == true)
        #expect(settings.scrollbackLines == 1000)
        #expect(settings.cursorColor == nil)
        #expect(settings.selectionColor == nil)
        #expect(settings.backgroundOpacity == 1.0)
    }

    @Test("background opacity resolves and clamps to 0.2...1.0")
    func backgroundOpacityClamps() {
        var settings = TerminalSettings()
        settings.backgroundOpacity = 0.05
        #expect(TerminalAppearanceResolver.resolve(settings: settings, theme: .neonBlue).backgroundOpacity == 0.2)
        settings.backgroundOpacity = 0.7
        #expect(TerminalAppearanceResolver.resolve(settings: settings, theme: .neonBlue).backgroundOpacity == 0.7)
    }

    @Test("appearance fields round-trip through the persistence store")
    func appearanceRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = TerminalSettings()
        settings.colorSchemeID = "dracula"
        settings.fontFamily = "Menlo"
        settings.fontSize = 15
        store.save(settings)

        let loaded = store.load(TerminalSettings.self)
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

    @Test("sendMouseEventsToApps defaults to true")
    func mouseForwardingDefaultsTrue() {
        #expect(TerminalSettings().sendMouseEventsToApps == true)
    }

    @Test("a legacy payload without sendMouseEventsToApps decodes to true")
    func mouseForwardingLegacyDefaultsTrue() throws {
        let legacy = Data(#"{"defaultShell":"/bin/zsh"}"#.utf8)
        let decoded = try JSONDecoder().decode(TerminalSettings.self, from: legacy)
        #expect(decoded.sendMouseEventsToApps == true)
    }

    @Test("sendMouseEventsToApps round-trips through the persistence store")
    func mouseForwardingRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = TerminalSettings()
        settings.sendMouseEventsToApps = false
        store.save(settings)
        #expect(store.load(TerminalSettings.self)?.sendMouseEventsToApps == false)
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
        #expect(dflt.fontFamily == "MesloLGS NF")
        #expect(dflt.fontSize == 15)

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

    @Test("Cursor/scrollback/behavior fields pass through to the resolved appearance")
    func behaviorFieldsResolve() {
        var settings = TerminalSettings()
        settings.cursorShape = .bar
        settings.cursorBlink = false
        settings.optionAsMeta = false
        settings.scrollbackLines = 5000
        let r = TerminalAppearanceResolver.resolve(settings: settings, theme: .neonBlue)
        #expect(r.cursorShape == .bar)
        #expect(r.cursorBlink == false)
        #expect(r.optionAsMeta == false)
        #expect(r.scrollback == 5000)
    }

    @Test("An explicit cursor color overrides the scheme cursor; selection has a default")
    func colorOverridesResolve() {
        var settings = TerminalSettings()
        settings.cursorColor = "FF0000"
        let r = TerminalAppearanceResolver.resolve(settings: settings, theme: .neonBlue)
        #expect(r.cursor == "FF0000")
        #expect(!r.selection.isEmpty)

        settings.selectionColor = "00FF00"
        #expect(TerminalAppearanceResolver.resolve(settings: settings, theme: .neonBlue).selection == "00FF00")
    }
}
