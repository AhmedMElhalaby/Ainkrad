import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Assistant's Settings surface (rendered inside the BUILT-IN APPS
/// section of `SettingsOverlayView`), organized into a tab shell —
/// Models (connections + model + effort), Access (permissions + sandbox),
/// Data (context privacy), Voice, and Appearance (surface opacity/blur +
/// assistant text font/size). The section builders live in
/// `AssistantSettingsView+Sections.swift`.
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
    @State var newAuthMode: AuthMode = .apiKey
    @State var revealedConnectionIDs: Set<UUID> = []
    @State var modelPicker = AssistantModelPickerModel()
    @State var testResults: [UUID: ConnectionTestResult] = [:]
    @State var testingIDs: Set<UUID> = []
    @State var hoveredConnectionID: UUID?
    @State private var selectedTab: AssistantSettingsTab = .models

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            AssistantSettingsTabBar(selection: $selectedTab, tokens: tokens)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(selectedTab.sections, id: \.self) { section in
                        sectionView(section, tokens: tokens)
                    }
                }
                .padding(18)
                .id(selectedTab)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
            }
            .scrollContentBackground(.hidden)
        }
        .animation(reduceMotion ? nil : AinkradMotion.present, value: selectedTab)
    }

    @ViewBuilder
    private func sectionView(_ section: AssistantSettingsSection, tokens: DesignTokens) -> some View {
        switch section {
        case .connections:    connectionsSection(tokens: tokens)
        case .model:          modelSection(tokens: tokens)
        case .permissions:    permissionsSection(tokens: tokens)
        case .sandbox:        sandboxSection(tokens: tokens)
        case .toolHooks:      toolHooksSection(tokens: tokens)
        case .contextPrivacy: contextPrivacySection(tokens: tokens)
        case .web:            webSection(tokens: tokens)
        case .media:          mediaSection(tokens: tokens)
        case .video:          videoSection(tokens: tokens)
        case .voice:          voiceSection(tokens: tokens)
        case .textToSpeech:   textToSpeechSection(tokens: tokens)
        case .appearance:     appearanceSection(tokens: tokens)
        }
    }
}
