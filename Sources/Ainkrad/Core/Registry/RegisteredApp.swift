import SwiftUI

/// Where a registered app comes from.
enum AppSource: Equatable {
    case builtIn
    case plugin(url: URL, apiVersion: Int)
}

/// The host-side value the registry holds — the single representation both
/// compiled-in `BuiltInApp`s and dynamically-loaded `AinkradApp` bundles map
/// into. View factories are closures so the concrete app type never leaks.
struct RegisteredApp: Identifiable {
    let id: String
    let displayName: String
    let icon: String
    let isEnabledByDefault: Bool
    let source: AppSource
    let makeRootView: @MainActor () -> AnyView
    let makeSettingsView: @MainActor () -> AnyView
    let chromeFill: @MainActor () -> Color?
}

/// A bundle the loader skipped, surfaced for the later Marketplace UI.
struct PluginLoadFailure: Equatable {
    let url: URL
    let reason: String
}

extension RegisteredApp {
    /// Adapts a compiled-in `BuiltInApp` type. `chromeFill` captures the live
    /// `AppEnvironment` so Terminal's header fill resolves exactly as before.
    @MainActor
    static func builtIn(_ app: BuiltInApp.Type, environment: AppEnvironment) -> RegisteredApp {
        RegisteredApp(
            id: app.id,
            displayName: app.displayName,
            icon: app.icon,
            isEnabledByDefault: app.isEnabledByDefault,
            source: .builtIn,
            makeRootView: { app.makeRootView() },
            makeSettingsView: { app.makeSettingsView() },
            chromeFill: { app.chromeFill(environment: environment) }
        )
    }
}
