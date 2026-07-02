import SwiftUI

/// Terminal's `BuiltInApp` conformance — see
/// Built-in App System & Registry.md.
struct TerminalApp: BuiltInApp {
    static let id = "terminal"
    static let displayName = "Terminal"
    static let icon = "terminal"
    static let isEnabledByDefault = true

    static func makeRootView() -> AnyView {
        AnyView(TerminalBlockRootView())
    }

    static func makeSettingsView() -> AnyView {
        AnyView(TerminalSettingsView())
    }
}
