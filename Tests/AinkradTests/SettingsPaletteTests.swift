import Testing
@testable import Ainkrad

@Suite("Settings search mode")
struct SettingsPaletteTests {
    @Test("an empty query browses")
    func emptyBrowses() {
        #expect(SettingsSearchMode(query: "", hasNavigated: false) == .browsing)
        #expect(SettingsSearchMode(query: "   ", hasNavigated: true) == .browsing)
    }

    @Test("typing opens the palette")
    func typingOpensPalette() {
        #expect(SettingsSearchMode(query: "blur", hasNavigated: false) == .palette("blur"))
    }

    @Test("navigating with a live query switches to filtering, not palette")
    func navigatingFilters() {
        #expect(SettingsSearchMode(query: "blur", hasNavigated: true) == .filtering("blur"))
    }
}
