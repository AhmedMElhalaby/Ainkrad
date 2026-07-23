import SwiftUI

/// Dev-only host that loads and renders a developer's plugin bundle through
/// the shared `AinkradHostRuntime` — the same validation and load path the
/// real host and store review use, so what a developer sees here matches
/// what ships. Logging/rejection-banner UI land in Task 4.
@main
struct DevHostApp: App {
    @State private var model = DevHostModel()

    var body: some Scene {
        WindowGroup("Ainkrad Dev Host") {
            PluginStageView(state: model.state)
                .onAppear {
                    guard case .empty = model.state else { return }
                    switch LaunchArguments.parse(Array(CommandLine.arguments.dropFirst())) {
                    case .success(let args):
                        model.load(args)
                    case .failure:
                        // No/invalid --bundle: leave `.empty` — this is a
                        // dev-only host, not a crash-worthy condition.
                        break
                    }
                }
        }
        .defaultSize(width: 800, height: 600)
    }
}
