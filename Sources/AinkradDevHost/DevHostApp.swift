import SwiftUI

/// Dev-only host that will load and render a developer's plugin bundle
/// through the shared `AinkradHostRuntime`, wired up in a later task. This is
/// a scaffold: loading/rendering/logging land in later tasks.
@main
struct DevHostApp: App {
    var body: some Scene {
        WindowGroup("Ainkrad Dev Host") {
            Text("Ainkrad Dev Host")
        }
        .defaultSize(width: 800, height: 600)
    }
}
