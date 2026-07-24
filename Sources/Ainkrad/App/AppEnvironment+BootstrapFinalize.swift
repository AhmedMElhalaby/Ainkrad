import Foundation
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// `AppEnvironment.bootstrap(rootURL:defaults:)` split into cohesive helpers
/// (M7 finalize Wave D, D2) — this file holds the final, post-construction
/// wiring block: it runs AFTER the real `AppEnvironment` instance exists, so
/// closures can capture it (weakly) directly, mirroring `bootstrap()`'s
/// original order exactly.
extension AppEnvironment {
    static func finalizeBootstrap(
        environment: AppEnvironment,
        connectionStore: ConnectionStore,
        localModelProbe: LocalModelProbe,
        localModelAvailability: LocalModelAvailability,
        mcpServerRegistry: MCPServerRegistry,
        lspServerRegistry: LSPServerRegistry,
        persistence: PersistenceStore,
        secrets: SecretStore,
        themeManager: ThemeManager,
        agentContextHub: AgentContextRegistryHub,
        agentActionHub: AgentActionRegistryHub,
        pluginLaunchHub: PluginLaunchHub,
        appAppearanceStore: AppAppearanceStore,
        pluginDataRoot: URL,
        pluginDirs: [URL],
        loader: PluginLoader,
        registry: BuiltInAppRegistry,
        workspaceManager: WorkspaceManager,
        defaults: UserDefaults
    ) {
        // Built after `environment` exists so the content closure can inject
        // `self` for `MenuBarPopoverView`'s `.environment(_:)` — mirrors how
        // `launcherStore.presentOverlay`/`pluginLaunchHub` below capture
        // `[weak environment]` rather than being wired inside the initializer.
        environment.menuBarController = MenuBarController(presence: environment.menuBarPresence) { [weak environment] in
            guard let environment else { return AnyView(EmptyView()) }
            return AnyView(MenuBarPopoverView(presence: environment.menuBarPresence).environment(environment))
        }

        // Launch-time external I/O (local-model probes, MCP connect, LSP
        // autodetect) is skipped when the app is hosting a test bundle: under
        // `xcodebuild test` these otherwise hang the shared process on network
        // timeouts / a TCC prompt, starving the tests. See
        // `AppEnvironment.isRunningUnderTests`. Guarded as one block since all
        // three are the same "background external I/O off the launch path" class.
        if !AppEnvironment.isRunningUnderTests {
            // Kick the local-reachability cache: an immediate refresh so the very
            // first turn already reflects reality (best-effort — a turn started
            // before this completes just sees the cache's initial empty state,
            // which is safe: local candidates are dropped, not hung on), then a
            // 30s repeating loop so a server started/stopped mid-session is
            // picked up without requiring a model-picker visit. Runs for the
            // process lifetime of `environment`, mirroring other bootstrap-owned
            // background loops in this app (e.g. sound/theme observers).
            Task { [weak connectionStore, weak localModelProbe] in
                while !Task.isCancelled {
                    guard let connectionStore, let localModelProbe else { return }
                    await localModelAvailability.refresh(
                        connections: connectionStore.connections, probe: localModelProbe,
                        tokenFor: { connectionStore.token(for: $0) })
                    try? await Task.sleep(for: .seconds(30))
                }
            }

            // Connect enabled MCP servers off the launch path: `connectEnabled()` is async
            // and per-server bounded/degrade-don't-crash (see `MCPServerRegistry`), but
            // launch itself must never block on a slow or down server, so this is fired
            // from an unawaited `Task` rather than run synchronously in `bootstrap()`.
            // Tools/trust populate as servers come up; a down server just never appears.
            Task { [weak mcpServerRegistry] in
                await mcpServerRegistry?.connectEnabled()
            }

            // Seed autodetected LSP servers off the launch path: `autodetect()` shells out to
            // `which` once per known server (a handful of `Process` spawns), so it runs inside
            // this unawaited `Task` rather than synchronously in `bootstrap()`. `seedIfEmpty`
            // is a no-op once the user has any configs (from a prior autodetect or a manual
            // edit in the LSP config UI), so this only ever does something on first launch.
            Task { [weak lspServerRegistry] in
                let configs = LSPServerRegistry.autodetect()
                await lspServerRegistry?.seedIfEmpty(with: configs)
            }
        }

        // Terminal ships as an App Store plugin (AinkradTerminal), not compiled in.
        // Still migrate any pre-4a host-global settings into its scoped store so the
        // installed plugin sees the user's existing configuration.
        let terminalHost = HostServicesImpl(appID: "terminal", dataRootURL: pluginDataRoot,
                                            secretStore: secrets, themeManager: themeManager,
                                            hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                                            declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)
        TerminalSettingsMigration.runIfNeeded(
            legacyRawPayload: { (persistence as? FileDocumentStore)?.rawPayloadData(forID: $0) },
            scoped: terminalHost.documents, defaults: defaults)

        // Assistant is a host-embedded built-in (its views read `AppEnvironment`
        // directly), scoped like any other app for its documents/secrets/theme/context.
        let assistantHost = HostServicesImpl(appID: "assistant", dataRootURL: pluginDataRoot,
                                             secretStore: secrets, themeManager: themeManager,
                                             hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                                             declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        // Live Canvas (M7 Slice 7) is likewise a host-embedded built-in — its
        // pane reads `AppEnvironment.canvasStore` directly (see `CanvasApp`).
        let canvasHost = HostServicesImpl(appID: "canvas", dataRootURL: pluginDataRoot,
                                          secretStore: secrets, themeManager: themeManager,
                                          hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                                          declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        let loaded = loader.loadAll(from: pluginDirs)
        registry.install(
            builtIn: [
                RegisteredApp.builtIn(
                    AssistantApp.self,
                    summary: "Your in-workspace AI assistant — chat about your code, run gated tools, and drive the terminal and git without leaving Ainkrad.",
                    host: assistantHost,
                    // Reading `surfaceOpacity` inside this closure — invoked
                    // synchronously from `TileLayoutView.hasTranslucentPane`
                    // and `BlockView.headerBackground` during their view
                    // bodies — registers an @Observable dependency, so dialing
                    // the slider live re-evaluates the backdrop + header.
                    chromeFillOverride: {
                        AssistantApp.surfaceFill(
                            opacity: appAppearanceStore.surfaceOpacity("assistant"),
                            base: themeManager.tokens.background
                        )
                    }
                ),
                RegisteredApp.builtIn(
                    CanvasApp.self,
                    summary: "The Live Canvas — the assistant lays out tables, diagrams, charts, code and status as movable HUD cards.",
                    host: canvasHost)
            ],
            loaded: loaded.apps,
            failures: loaded.failures
        )

        if let saved = persistence.load(LayoutStateSnapshot.self) {
            workspaceManager.restore(from: saved)
            workspaceManager.pruneApps(keeping: Set(registry.allApps.map { $0.id }))
            Log.app.info("Restored workspace layout: \(saved.workspaces.count) workspace(s)")
        }
        workspaceManager.onStateChange = { [weak workspaceManager] in
            guard let workspaceManager else { return }
            persistence.save(workspaceManager.snapshot())
        }

        environment.launcherStore.presentOverlay = { [weak environment] appID in
            environment?.presentedOverlayAppID = appID
        }

        // Captures `[weak environment]` (rather than `[weak workspaceManager]`,
        // as pre-Slice-3) so it can also clear `presentedOverlayAppID` — any
        // app opening (tiled or via this hub) dismisses a summoned plugin
        // overlay, mirroring the Settings/App Store overlays' dismiss-on-open.
        pluginLaunchHub.setOpenHandler { [weak environment] appID in
            guard let environment else { return }
            let declared = environment.registry.allApps.first { $0.id == appID }?.presentation ?? .pane
            let effective = environment.appAppearanceStore.presentationOverride(appID) ?? declared
            if effective == .overlay {
                environment.presentedOverlayAppID = appID
            } else {
                environment.workspaceManager.activeWorkspace.tileLayout.openApp(appID)
                environment.presentedOverlayAppID = nil
            }
        }

        Log.app.info("AppEnvironment bootstrapped with \(registry.allApps.count) registered app(s)")
    }
}
