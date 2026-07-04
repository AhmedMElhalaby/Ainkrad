import SwiftUI
import AinkradAppKit

/// A minimal loadable app that proves the SDK + loader path end to end:
/// theme-tinted rendering, and a toggle persisted through scoped documents.
struct HelloApp: AinkradApp {
    static let id = "hello"
    static let displayName = "Hello"
    static let icon = "hand.wave"

    static func makeRootView(host: HostServices) -> AnyView { AnyView(HelloRootView(host: host)) }
    static func makeSettingsView(host: HostServices) -> AnyView { AnyView(Text("Hello settings")) }
}

private struct HelloRootView: View {
    let host: HostServices
    @State private var on: Bool

    init(host: HostServices) {
        self.host = host
        _on = State(initialValue: host.documents.data(forKey: "on") == Data([1]))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Hello, Ainkrad 👋")
                .font(.largeTitle)
                .foregroundStyle(host.theme.accentPrimary)
            Toggle("Remembered switch", isOn: $on)
                .onChange(of: on) { _, value in
                    host.documents.setData(Data([value ? 1 : 0]), forKey: "on")
                    host.log.info("toggle set to \(value)")
                }
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(host.theme.background)
    }
}

/// The bundle's principal class. `@objc` + explicit name so the Info.plist's
/// `NSPrincipalClass` resolves it after `Bundle.load()`.
@objc(HelloEntryPoint)
final class HelloEntryPoint: NSObject, AinkradPluginEntryPoint {
    static func app() -> any AinkradApp.Type { HelloApp.self }
}
