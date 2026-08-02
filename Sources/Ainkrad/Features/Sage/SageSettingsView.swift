import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Sage's own app-settings surface (rendered under BUILT-IN APPS in
/// `SettingsOverlayView`).
///
/// Everything about the *agent* — connections, model, permissions, sandbox,
/// tool hooks, remote channel, context privacy, web/media/video tools — now
/// lives as its own top-level page under INTELLIGENCE
/// (`IntelligenceSettingsCatalog`), and voice/text-to-speech under WORKSPACE ▸
/// Sound & Voice. The section builders themselves are unchanged; they moved
/// into standalone views in `SageSettingsView+Sections.swift` /
/// `+Connections.swift`. What went away is the nested pill bar, not the UI.
///
/// What remains here is what is genuinely app-specific: the Sage's
/// appearance (surface opacity, blur, and its own message font/size).
struct SageSettingsView: View {
    // Note: not `private` — the appearance builder in
    // `SageSettingsView+Sections.swift` needs access, and Swift's
    // `private` only extends to same-file extensions of this type.
    @Environment(AppEnvironment.self) var environment

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 20) {
            appearanceSection(tokens: tokens)
        }
    }
}
