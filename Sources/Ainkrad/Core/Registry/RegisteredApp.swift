import SwiftUI
import AinkradAppKit
import protocol AinkradAppKit.AinkradApp

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
    /// Adapts a compiled-in app that conforms to the SDK `AinkradApp` contract,
    /// binding it to its scoped host services. `source == .builtIn`, so the
    /// registry gives it priority over any same-id plugin.
    @MainActor
    static func builtIn(_ app: any AinkradApp.Type, isEnabledByDefault: Bool = true, host: HostServices) -> RegisteredApp {
        RegisteredApp(
            id: app.id,
            displayName: app.displayName,
            icon: app.icon,
            isEnabledByDefault: isEnabledByDefault,
            source: .builtIn,
            makeRootView: { app.makeRootView(host: host) },
            makeSettingsView: { app.makeSettingsView(host: host) },
            chromeFill: { app.chromeFill(host: host) }
        )
    }
}
