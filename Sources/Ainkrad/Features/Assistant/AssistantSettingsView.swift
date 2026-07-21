import SwiftUI
import AinkradAppKit

/// The Assistant's Settings surface (rendered inside the BUILT-IN APPS
/// section of `SettingsOverlayView`): Connections (API keys), Model
/// (provider/model/effort), Permissions, and Context privacy (per-source
/// opt-outs).
struct AssistantSettingsView: View {
    // Note: not `private` — the section builders in
    // `AssistantSettingsView+Sections.swift` need access, and Swift's
    // `private` only extends to same-file extensions of this type.
    @Environment(AppEnvironment.self) var environment
    @Environment(\.ainkradReduceMotion) var reduceMotion

    @State var newPreset: ProviderPreset = ProviderPreset.preset(id: "openai")
    @State var newBaseURL: String = ProviderPreset.preset(id: "openai").defaultBaseURL
    @State var newDisplayName: String = ""
    @State var newConnectionToken = ""
    @State var revealedConnectionIDs: Set<UUID> = []
    @State var modelPicker = AssistantModelPickerModel()
    @State var testResults: [UUID: ConnectionTestResult] = [:]
    @State var testingIDs: Set<UUID> = []
    @State var hoveredConnectionID: UUID?

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionsSection(tokens: tokens)
                modelSection(tokens: tokens)
                permissionsSection(tokens: tokens)
                sandboxSection(tokens: tokens)
                contextPrivacySection(tokens: tokens)
                voiceSection(tokens: tokens)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }
}
