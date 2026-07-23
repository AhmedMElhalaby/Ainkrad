import SwiftUI
import AinkradHostRuntime

/// Slice 3's floating host overlay for `.overlay`-presentation plugin apps —
/// summoned from the Launcher instead of tiling into the workspace layout.
/// Mirrors `LauncherView`'s scrim + `hudPanelChrome` panel composition, but
/// hosts a `RegisteredApp`'s own root view rather than the app-picker UI.
struct PluginOverlayView: View {
    let app: RegisteredApp
    let tokens: DesignTokens
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                app.makeRootView()
                    .frame(width: min(max(560, geo.size.width * 0.42), 700),
                           height: min(max(460, geo.size.height * 0.66), 760))
                    .hudPanelChrome(tokens: tokens)
                    .focusable()
                    .focused($isFocused)
                    .focusEffectDisabled()
                    .onKeyPress(.escape) { onDismiss(); return .handled }
                    .offset(y: -28)
            }
        }
        .onAppear { isFocused = true }
    }
}
