import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Renders the current `DevHostModel.State`. `.loaded` renders the plugin's
/// own root view via its `makeRootView` factory, honoring the bundle's
/// declared presentation; `.empty`/`.invalid` render a minimal placeholder.
/// Deliberately minimal — the log pane + rejection banner land in Task 4.
struct PluginStageView: View {
    let state: DevHostModel.State

    var body: some View {
        switch state {
        case .empty:
            placeholder("No bundle loaded", systemImage: "app.dashed")
        case .invalid(let message):
            placeholder(message, systemImage: "exclamationmark.triangle")
        case .loaded(let app):
            switch app.presentation {
            case .pane:
                app.makeRootView()
            case .overlay:
                app.makeRootView()
                    .background(.regularMaterial)
            @unknown default:
                app.makeRootView()
            }
        }
    }

    private func placeholder(_ message: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
