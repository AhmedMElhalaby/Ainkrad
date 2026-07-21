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
    @Test("titles and icons are set for every tab") func metadata() {
        for tab in AssistantSettingsTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.icon.isEmpty)
        }
    }
}
