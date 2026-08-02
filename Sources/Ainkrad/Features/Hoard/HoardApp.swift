import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The compiled-in Hoard app — a keyboard-driven, git-aware file browser.
/// Host-embedded rather than a real plugin (same as `AssistantApp` and
/// `CanvasApp`): its views read `AppEnvironment` directly via
/// `@Environment(AppEnvironment.self)`, so `host` is unused here beyond
/// satisfying the registration contract shared with dynamically-loaded
/// `AinkradApp`s.
enum HoardApp: AinkradApp {
    static let id = "hoard"
    static let displayName = "Hoard"
    static let icon = "folder"

    static func makeRootView(host: HostServices) -> AnyView {
        AnyView(HoardRootView())
    }

    static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(EmptyView())
    }

    /// The pane's window fill for a given surface opacity — the same contract
    /// `AssistantApp` implements, and the mechanism that makes a pane
    /// translucent at all.
    ///
    /// Returning a sub-opaque color is what drives the whole chain:
    /// `TileLayoutView.hasTranslucentPane` then renders the shared blurred
    /// sky+island backdrop behind the pane, and `BlockView.headerBackground`
    /// adopts this same fill so the title bar is one continuous surface with
    /// the body instead of an opaque bar sitting on glass. `nil` means opaque —
    /// no backdrop, no cost. Pure + host-independent so it is unit-testable
    /// without `AppEnvironment`.
    static func surfaceFill(opacity: Double, base: Color) -> Color? {
        opacity < 1 ? base.opacity(opacity) : nil
    }

    /// Hoard' own settings. Declared as real fields rather than a wrapped view:
    /// the `nil` path makes `AppSettingsCatalog` fall back to wrapping
    /// `makeSettingsView` in a `.custom` field, which is the wrap-a-view decay
    /// that `SettingsKitCompositionTests`' ratchet rejects.
    static func settingsCatalog(host: HostServices) -> SettingsPage? {
        // Built by `HoardSettingsCatalog` against `AppEnvironment`, which this
        // static entry point cannot see. The host calls the environment-aware
        // builder directly; this returns the shape with no groups so the page
        // still exists and stays searchable if that wiring is ever bypassed.
        SettingsPage(
            path: SettingsPath(["app", id]),
            title: displayName,
            icon: icon,
            group: .builtInApps,
            order: 0,
            groups: [],
            appID: id
        )
    }
}
