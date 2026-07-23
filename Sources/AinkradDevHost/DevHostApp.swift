import SwiftUI

/// Dev-only host that loads and renders a single developer plugin bundle,
/// validated and serviced by the real host's `AinkradHostRuntime`. This is a
/// scaffold: loading/rendering/logging land in later tasks.
@main
struct DevHostApp: App {
    var body: some Scene {
        WindowGroup("Ainkrad Dev Host") {
            Text("Ainkrad Dev Host")
        }
        .defaultSize(width: 800, height: 600)
    }
}
