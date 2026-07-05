import SwiftUI
import AinkradAppKit

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

    /// The header matches the terminal window: the resolved scheme background
    /// at the configured transparency, so the title bar is the same color and
    /// opacity as the terminal below it (revealing the same blurred island when
    /// translucent) and the pane reads as one continuous window.
    static func chromeFill(environment: AppEnvironment) -> Color? {
        let appearance = TerminalAppearanceResolver.resolve(
            settings: environment.terminalSettingsStore.settings,
            tokens: HostThemeTokens(from: environment.themeManager.currentTheme)
        )
        return Color(hex: appearance.background).opacity(appearance.backgroundOpacity)
    }
}
