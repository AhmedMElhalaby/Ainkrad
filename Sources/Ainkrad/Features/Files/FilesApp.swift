import SwiftUI
import AinkradAppKit

/// The compiled-in Files app — a keyboard-driven, git-aware file browser.
/// Host-embedded rather than a real plugin (same as `AssistantApp` and
/// `CanvasApp`): its views read `AppEnvironment` directly via
/// `@Environment(AppEnvironment.self)`, so `host` is unused here beyond
/// satisfying the registration contract shared with dynamically-loaded
/// `AinkradApp`s.
enum FilesApp: AinkradApp {
    static let id = "files"
    static let displayName = "Files"
    static let icon = "folder"

    static func makeRootView(host: HostServices) -> AnyView {
        AnyView(FilesRootView())
    }

    static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(EmptyView())
    }

    /// Files has no settings of its own yet, but it must still DECLARE an
    /// (empty) catalog rather than leaving this `nil`. The `nil` path makes
    /// `AppSettingsCatalog` fall back to wrapping `makeSettingsView` in a
    /// `.custom` field — the wrap-a-view decay that
    /// `SettingsKitCompositionTests`' ratchet exists to reject. Declaring no
    /// groups yields a page carrying only the host-owned Appearance group,
    /// which is exactly right for an app with nothing else to configure.
    ///
    /// When M5 adds the opt-in `hjkl` layer, its toggle becomes the first real
    /// group here — as a declared field, never a wrapped view.
    static func settingsCatalog(host: HostServices) -> SettingsPage? {
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
