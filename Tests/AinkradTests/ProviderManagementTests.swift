import Testing
import Foundation
@testable import Ainkrad

@Suite("ProviderManagement")
@MainActor
struct ProviderManagementTests {
    @Test func imagePresetsAreValidHTTPSEndpoints() {
        #expect(!MediaSettingsView.imagePresets.isEmpty)
        for p in MediaSettingsView.imagePresets {
            #expect(!p.label.isEmpty)
            #expect(p.baseURL.hasPrefix("https://"))
        }
    }

    @Test func ttsPresetsAreValidHTTPSEndpoints() {
        #expect(!TTSSettingsView.ttsPresets.isEmpty)
        for p in TTSSettingsView.ttsPresets {
            #expect(!p.label.isEmpty)
            #expect(p.baseURL.hasPrefix("https://"))
        }
    }

    @Test func providerOptionEquatable() {
        let a = ProviderOption(id: "openai", label: "OpenAI", configured: true, keyless: false)
        let b = ProviderOption(id: "openai", label: "OpenAI", configured: true, keyless: false)
        #expect(a == b)
    }
}
