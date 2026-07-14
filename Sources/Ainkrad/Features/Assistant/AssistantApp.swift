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

    /// The Assistant's window fill for a given surface opacity. Translucent
    /// (so `TileLayoutView.hasTranslucentPane` triggers and the header unifies
    /// with the body) only when the user has dialed opacity below 1; `nil`
    /// means opaque — no backdrop, today's look. Pure + host-independent so it
    /// is unit-testable without `AppEnvironment`.
    static func surfaceFill(opacity: Double, base: Color) -> Color? {
        opacity < 1 ? base.opacity(opacity) : nil
    }
}
