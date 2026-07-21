import Foundation
import Testing
@testable import Ainkrad

@Suite("Assistant settings tabs")
struct AssistantSettingsTabTests {
    @Test("every section belongs to exactly one tab, and all are covered") func partition() {
        let all = AssistantSettingsTab.allCases.flatMap(\.sections)
        #expect(Set(all).count == all.count)                            // no section in two tabs
        #expect(Set(all) == Set(AssistantSettingsSection.allCases))     // no section missing
    }
    @Test("models tab is connections then model") func models() {
        #expect(AssistantSettingsTab.models.sections == [.connections, .model])
    }
    @Test("access tab is permissions then sandbox") func access() {
        #expect(AssistantSettingsTab.access.sections == [.permissions, .sandbox])
    }
    @Test("data tab is context privacy") func data() {
        #expect(AssistantSettingsTab.data.sections == [.contextPrivacy])
    }
    @Test("voice tab is voice") func voice() {
        #expect(AssistantSettingsTab.voice.sections == [.voice])
    }
    @Test("appearance tab is appearance") func appearance() {
        #expect(AssistantSettingsTab.appearance.sections == [.appearance])
    }
    @Test("titles and icons are set for every tab") func metadata() {
        for tab in AssistantSettingsTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.icon.isEmpty)
        }
    }
}

@Suite("App appearance font override")
@MainActor
struct AppAppearanceFontTests {
    private func store() -> AppAppearanceStore {
        AppAppearanceStore(persistence: InMemoryPersistenceStore())
    }
    @Test("font family/scale default to nil (inherit global)") func defaultsNil() {
        let s = store()
        #expect(s.fontFamily("assistant") == nil)
        #expect(s.fontScale("assistant") == nil)
    }
    @Test("set and read back a font family override") func familyRoundTrip() {
        let s = store()
        s.setFontFamily("assistant", .jetBrainsMono)
        #expect(s.fontFamily("assistant") == .jetBrainsMono)
    }
    @Test("set and read back a font scale override") func scaleRoundTrip() {
        let s = store()
        s.setFontScale("assistant", .large)
        #expect(s.fontScale("assistant") == .large)
    }
    @Test("clearing back to nil restores inherit") func clears() {
        let s = store()
        s.setFontFamily("assistant", .system)
        s.setFontFamily("assistant", nil)
        #expect(s.fontFamily("assistant") == nil)
    }
    @Test("font override is independent of opacity/blur on the same entry") func independent() {
        let s = store()
        s.setSurfaceOpacity("assistant", 0.5)
        s.setFontScale("assistant", .small)
        #expect(s.surfaceOpacity("assistant") == 0.5)
        #expect(s.fontScale("assistant") == .small)
    }
}

@Suite("Assistant typography resolver")
struct AssistantTypographyTests {
    @Test("nil override inherits global family and scale") func inherits() {
        let t = AssistantTypography.resolve(family: nil, scale: nil,
                                            globalFamily: .exo2, globalScale: .medium)
        #expect(t.family == .exo2)
        #expect(t.scale == UIFontScale.medium.multiplier)
    }
    @Test("override wins over global") func overrides() {
        let t = AssistantTypography.resolve(family: .jetBrainsMono, scale: .large,
                                            globalFamily: .exo2, globalScale: .small)
        #expect(t.family == .jetBrainsMono)
        #expect(t.scale == UIFontScale.large.multiplier)
    }
    @Test("partial override: family only, scale inherits") func partial() {
        let t = AssistantTypography.resolve(family: .system, scale: nil,
                                            globalFamily: .exo2, globalScale: .large)
        #expect(t.family == .system)
        #expect(t.scale == UIFontScale.large.multiplier)
    }
}
