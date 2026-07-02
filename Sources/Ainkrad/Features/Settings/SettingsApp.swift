import SwiftUI

/// Settings' `BuiltInApp` conformance — Settings is a Block opened from
/// the Launcher like any other app, not a macOS `Settings {}` scene. Its
/// own settings view is empty: Settings has no per-app settings of its
/// own; its content IS the settings surface. See Navigation & Settings
/// Architecture.md.
struct SettingsApp: BuiltInApp {
    static let id = "settings"
    static let displayName = "Settings"
    static let icon = "gearshape"
    static let isEnabledByDefault = true

    static func makeRootView() -> AnyView {
        AnyView(SettingsRootView())
    }

    static func makeSettingsView() -> AnyView {
        AnyView(EmptyView())
    }
}
