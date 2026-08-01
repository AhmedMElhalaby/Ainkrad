import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Pure mapping used by the menu-bar presence indicator (unit-tested; keeps the
/// SwiftUI view thin).
enum RemoteChannelPresence {
    static func isListening(_ status: RemoteChannelStatus) -> Bool { status == .listening }
}

/// Cardinal HUD settings panel for the remote channel. Off by default; the
/// toggle enables it, "Generate token" writes to the Keychain, the endpoint URL
/// is shown for copy. NO native controls — only AinkradAppKit HUD controls.
@MainActor
struct RemoteChannelSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var settingsStore: RemoteChannelSettingsStore
    let service: RemoteChannelService

    var body: some View {
        let tokens = environment.themeManager.tokens

        AinkradSettingsPanel(title: "Remote channel",
                             hint: "Drive the assistant from outside the app.") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Drive this agent off-machine over a local, token-authenticated HTTP endpoint. Off by default; binds to 127.0.0.1 only — no external network exposure.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                AinkradFormRow(title: "Enable remote channel",
                               help: "Starts a local listener once a token exists") {
                    AinkradToggle(isOn: Binding(
                        get: { settingsStore.settings.enabled },
                        set: { settingsStore.setEnabled($0); service.applyEnabledState() }))
                }

                HStack(spacing: 10) {
                    AinkradButton(title: settingsStore.token == nil ? "Generate token" : "Rotate token",
                                  style: .secondary) {
                        _ = settingsStore.rotateToken()
                        service.applyEnabledState()
                    }
                    if settingsStore.token != nil {
                        AinkradButton(title: "Clear token", style: .ghost) {
                            settingsStore.clearToken()
                            service.applyEnabledState()
                        }
                    }
                }

                Text(statusLine)
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusLine: String {
        switch service.status {
        case .off: return "Disabled."
        case .needsToken: return "Enabled — generate a token to start listening."
        case .listening: return "Listening on 127.0.0.1:\(settingsStore.settings.port)  ·  POST /hook"
        case .stopped: return "Stopped."
        }
    }
}
