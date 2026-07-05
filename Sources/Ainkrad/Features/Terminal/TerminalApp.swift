import SwiftUI
import AinkradAppKit

/// Terminal as an `AinkradApp` — the SDK contract. Compiled into the host for
/// now (slice 4a); slice 4b extracts it into its own catalog bundle. Depends
/// only on `HostServices`, never on `AppEnvironment`.
struct TerminalApp: AinkradApp {
    static let id = "terminal"
    static let displayName = "Terminal"
    static let icon = "terminal"

    static func makeRootView(host: HostServices) -> AnyView {
        AnyView(TerminalBlockRootView(
            settingsStore: TerminalRuntime.settingsStore(for: host),
            theme: host.theme
        ))
    }

    static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(TerminalSettingsView(
            settingsStore: TerminalRuntime.settingsStore(for: host),
            theme: host.theme
        ))
    }

    /// The header matches the terminal window: the resolved scheme background at
    /// the configured transparency, so the title bar reads as one continuous
    /// surface with the terminal below.
    static func chromeFill(host: HostServices) -> Color? {
        let appearance = TerminalAppearanceResolver.resolve(
            settings: TerminalRuntime.settingsStore(for: host).settings,
            tokens: host.theme.tokens
        )
        return Color(hex: appearance.background).opacity(appearance.backgroundOpacity)
    }
}
