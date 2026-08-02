import SwiftUI
import AinkradAppKit

/// The compiled-in Live Canvas app — a tiled surface of agent-rendered layered
/// cards. Host-embedded (reads `AppEnvironment` directly like `SageApp`);
/// `host` satisfies the registration contract only.
enum CanvasApp: AinkradApp {
    static let id = "canvas"
    static let displayName = "Canvas"
    static let icon = "square.on.square"

    static func makeRootView(host: HostServices) -> AnyView { AnyView(CanvasHostView()) }
    static func makeSettingsView(host: HostServices) -> AnyView { AnyView(EmptyView()) }
}

/// Thin wrapper so the pane can pull `canvasStore` from the environment.
@MainActor
private struct CanvasHostView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View { CanvasView(store: environment.canvasStore) }
}
