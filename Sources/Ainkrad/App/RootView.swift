import SwiftUI

/// The single window's content: every workspace's tile layout stays
/// mounted (hidden when inactive) so running sessions survive switching;
/// the Launcher and Workspace Overview overlay on top when summoned.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    private var isOverlayPresented: Bool {
        environment.isLauncherPresented || environment.isWorkspaceOverviewPresented || environment.isSettingsPresented
            || environment.isAppStorePresented || environment.isQuickAskPresented || environment.quitCoordinator.isConfirming
            || environment.presentedOverlayAppID != nil
    }

    /// The app of the focused pane in the active workspace, so Settings can
    /// open directly on that app's section (e.g. Terminal when one is focused).
    private var focusedAppID: String? {
        let layout = environment.workspaceManager.activeWorkspace.tileLayout
        return layout.blocks.first { $0.id == layout.focusedBlockID }?.appID
    }

    var body: some View {
        ZStack {
            // Sky and workspace blur TOGETHER while an overlay is up —
            // blurring only the workspace would rasterize it separately
            // from the sky and visibly seam the composition.
            ZStack {
                AmbientSkyView()

                // Extends under the (hidden) title bar so the HUD is the
                // top of the screen itself — the traffic lights float
                // inside it. The bar is always shown; in full screen it also
                // carries the status readouts, and the traffic lights within
                // it reveal on top-edge hover (see `HUDBar`).
                VStack(spacing: 0) {
                    HUDBar()

                    // ALL workspaces stay in the hierarchy — switching
                    // only toggles visibility, so PTY-backed sessions in
                    // background workspaces keep running. They're laid out
                    // as a horizontal carousel: the active one sits at
                    // center, the others wait one screen-width to either
                    // side by their order, so switching slides the new
                    // workspace in from the direction it lives (spatially
                    // matching the HUD's workspace row).
                    workspaceCarousel
                }
                .ignoresSafeArea(edges: .top)
            }
            .blur(radius: isOverlayPresented ? 14 : 0)

            if environment.isLauncherPresented {
                LauncherView(store: environment.launcherStore) {
                    environment.isLauncherPresented = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if environment.isWorkspaceOverviewPresented {
                WorkspaceOverviewView {
                    environment.isWorkspaceOverviewPresented = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if environment.isSettingsPresented {
                SettingsOverlayView(focusedAppID: focusedAppID) {
                    environment.isSettingsPresented = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if environment.isAppStorePresented {
                AppStoreOverlayView(store: environment.appStoreStore) {
                    environment.isAppStorePresented = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if environment.isQuickAskPresented {
                QuickAskOverlayView {
                    environment.isQuickAskPresented = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if environment.quitCoordinator.isConfirming {
                QuitConfirmationView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if let id = environment.presentedOverlayAppID,
               let app = environment.registry.allApps.first(where: { $0.id == id }) {
                PluginOverlayView(app: app, tokens: environment.themeManager.tokens) {
                    environment.presentedOverlayAppID = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: isOverlayPresented)
        .background(KeyboardShortcutMonitor(environment: environment))
        // Each HUD overlay plays `.overlayOpen`/`.overlayClose` as it's
        // summoned/dismissed (AIN-108) — centralized here rather than in each
        // overlay view, since presentation is already driven by these four
        // flags on `environment`. Distinct from `.appLaunch`/`.appQuit`,
        // which are reserved for the Ainkrad app itself starting/quitting.
        .onChange(of: environment.isLauncherPresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        .onChange(of: environment.isSettingsPresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        .onChange(of: environment.isAppStorePresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        .onChange(of: environment.isWorkspaceOverviewPresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        .onChange(of: environment.isQuickAskPresented) { _, isPresented in
            environment.sounds.play(isPresented ? .overlayOpen : .overlayClose)
        }
        // Switching the active workspace (⌘1-9, ⌥Tab, cycle, HUD dots all
        // funnel through this one property) plays `.workspaceSwitch`.
        // `onChange` without `initial: true` never fires for the value the
        // view first appears with, so this doesn't fire on launch.
        .onChange(of: environment.workspaceManager.activeWorkspaceID) { _, _ in
            environment.sounds.play(.workspaceSwitch)
        }
    }

    private var workspaceCarousel: some View {
        GeometryReader { proxy in
            let manager = environment.workspaceManager
            let activeIndex = manager.workspaces.firstIndex { $0.id == manager.activeWorkspaceID } ?? 0

            ZStack {
                ForEach(Array(manager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    let isActive = index == activeIndex
                    TileLayoutView(workspace: workspace, registry: environment.registry)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(isActive ? 1 : 0)
                        .offset(x: CGFloat(index - activeIndex) * proxy.size.width)
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .animation(.spring(response: 0.42, dampingFraction: 0.88), value: manager.activeWorkspaceID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
