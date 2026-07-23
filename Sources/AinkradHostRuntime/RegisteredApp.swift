import SwiftUI
import AinkradAppKit
import protocol AinkradAppKit.AinkradApp

/// Where a registered app comes from.
public enum AppSource: Equatable {
    case builtIn
    case plugin(url: URL, apiVersion: Int)
}

/// The host-side value the registry holds — the single representation both
/// compiled-in `BuiltInApp`s and dynamically-loaded `AinkradApp` bundles map
/// into. View factories are closures so the concrete app type never leaks.
public struct RegisteredApp: Identifiable {
    public let id: String
    public let displayName: String
    public let icon: String
    /// Short App Store description for built-ins (which have no catalog entry).
    /// Empty for plugins — their description comes from the catalog. Defaulted
    /// so existing construction sites are unaffected.
    public var summary: String = ""
    public let isEnabledByDefault: Bool
    public let source: AppSource
    public let makeRootView: @MainActor () -> AnyView
    public let makeSettingsView: @MainActor () -> AnyView
    public let chromeFill: @MainActor () -> Color?
    /// How the app's window should be presented (Slice 3): tiled into the
    /// workspace layout (`.pane`, the default) or summoned as a floating
    /// host overlay (`.overlay`) that auto-dismisses when any app opens.
    public var presentation: PluginPresentation = .pane

    public init(id: String, displayName: String, icon: String, summary: String = "",
                isEnabledByDefault: Bool, source: AppSource,
                makeRootView: @escaping @MainActor () -> AnyView,
                makeSettingsView: @escaping @MainActor () -> AnyView,
                chromeFill: @escaping @MainActor () -> Color?,
                presentation: PluginPresentation = .pane) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.summary = summary
        self.isEnabledByDefault = isEnabledByDefault
        self.source = source
        self.makeRootView = makeRootView
        self.makeSettingsView = makeSettingsView
        self.chromeFill = chromeFill
        self.presentation = presentation
    }
}

/// A bundle the loader skipped, surfaced for the later App Store UI.
public struct PluginLoadFailure: Equatable {
    public let url: URL
    public let reason: String
    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

extension RegisteredApp {
    /// Adapts a compiled-in app that conforms to the SDK `AinkradApp` contract,
    /// binding it to its scoped host services. `source == .builtIn`, so the
    /// registry gives it priority over any same-id plugin.
    @MainActor
    public static func builtIn(
        _ app: any AinkradApp.Type,
        isEnabledByDefault: Bool = true,
        summary: String = "",
        host: HostServices,
        chromeFillOverride: (@MainActor () -> Color?)? = nil
    ) -> RegisteredApp {
        RegisteredApp(
            id: app.id,
            displayName: app.displayName,
            icon: app.icon,
            summary: summary,
            isEnabledByDefault: isEnabledByDefault,
            source: .builtIn,
            makeRootView: { app.makeRootView(host: host) },
            makeSettingsView: { app.makeSettingsView(host: host) },
            // A built-in whose fill depends on host-side state the SDK
            // `chromeFill(host:)` can't see (e.g. the Assistant's appearance
            // store) supplies it here; otherwise fall back to the SDK path.
            chromeFill: chromeFillOverride ?? { app.chromeFill(host: host) },
            presentation: .pane
        )
    }
}
