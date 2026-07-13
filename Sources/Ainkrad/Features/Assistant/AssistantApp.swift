import SwiftUI
import AinkradAppKit

/// The compiled-in Assistant app — the tiled AgentKit chat surface. It is
/// host-embedded rather than a real plugin: its views read `AppEnvironment`
/// directly via `@Environment(AppEnvironment.self)` (same as the Settings
/// sections), so `host` is unused here beyond satisfying the registration
/// contract shared with dynamically-loaded `AinkradApp`s.
enum AssistantApp: AinkradApp {
    static let id = "assistant"
    static let displayName = "Assistant"
    static let icon = "sparkles"

    static func makeRootView(host: HostServices) -> AnyView {
        AnyView(AssistantRootView())
    }

    static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(AssistantSettingsView())
    }
}
