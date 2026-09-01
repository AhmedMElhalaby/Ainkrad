import Foundation
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// `AppEnvironment.bootstrap(home:defaults:)` split into cohesive helpers
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
        home: Home,
        defaults: UserDefaults
    ) {
        // Built after `environment` exists so the content closure can inject
        // `self` for `MenuBarPopoverView`'s `.environment(_:)` — mirrors how
        // `launcherStore.presentOverlay`/`pluginLaunchHub` below capture
        // `[weak environment]` rather than being wired inside the initializer.
        // MARK: Signal (notification feed)
        //
        // Built here rather than in `bootstrapCoreStores` because it needs the
        // sound engine, the window state, and `environment` itself for the
        // popover's content closure — the same reasons `menuBarController` is
        // built here.
        let signalPreferencesStore = SignalPreferencesStore(
            url: home.cacheRoot.deletingLastPathComponent()
                .appendingPathComponent("signal-preferences.json"))
        let signalContextProvider = HostDeliveryContextProvider()
        let signalCenter = AppEnvironment.makeSignalCenter(
            storeURL: AppEnvironment.signalStoreURL(
                applicationSupport: home.cacheRoot.deletingLastPathComponent()),
            preferences: signalPreferencesStore.load(),
            sound: environment.sounds,
            toast: environment.signalToasts,
            contextProvider: signalContextProvider,
            badge: { _ in
                // Per-app badges are M2's `SignalBadgeModel`; the menu-bar
                // badge is driven by `onUnreadChanged` below, which covers
                // every path that changes the count rather than only delivery.
            })
        // "Visible" means the app has a surface the user can actually see, so
        // routing can tell "you are looking at Raven" from "Raven is installed".
        // `isAppOpen` is the host's own answer to that question and covers both
        // tiled panes and overlay presentation.
        signalContextProvider.visibleAppIDs = { [weak environment] in
            guard let environment else { return [] }
            return Set(environment.registry.enabledApps.map(\.id)
                .filter { environment.isAppOpen($0) })
        }
        signalCenter.onRulesChanged = { [weak signalCenter] rules in
            guard let signalCenter else { return }
            signalPreferencesStore.save(
                SignalPreferences(rules: rules, retention: signalCenter.retention))
        }
        signalCenter.onRetentionChanged = { [weak signalCenter] retention in
            guard let signalCenter else { return }
            signalPreferencesStore.save(
                SignalPreferences(rules: signalCenter.rules, retention: retention))
        }
        environment.signalCenter = signalCenter
        // `RunManager` is built in `bootstrapSession`, before this runs, so the
        // center is attached rather than injected.
        environment.runManager.attachSignalCenter(signalCenter)

        environment.signalBellController = SignalBellController { [weak environment] in
            guard let environment, let center = environment.signalCenter else {
                return AnyView(EmptyView())
            }
            return AnyView(
                SignalBellPopover(
                    events: center.recent,
                    unread: center.totalUnread,
                    readIDs: [],
                    onActivate: { _ in },
                    onMarkAllRead: { center.markAllRead(filter: .all) },
                    onOpenFeed: {
                        environment.signalBellController?.hidePopover()
                        environment.isSignalFeedPresented = true
                    })
                    .environment(environment))
        }
        let bell = environment.signalBellController
        signalCenter.onUnreadChanged = { unread in
            bell?.updateBadge(unread: unread)
        }
        bell?.updateBadge(unread: signalCenter.totalUnread)

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

        // Rune (formerly Terminal) ships as an App Store plugin, not compiled in.
        // Still migrate any pre-4a host-global settings into its scoped store so the
        // installed plugin sees the user's existing configuration. Scoped to "rune":
        // `AppDataDirectoryRename` has already moved <Apps>/terminal to <Apps>/rune
        // earlier in bootstrap, so writing to the old id would strand this migration
        // in a directory the plugin no longer reads.
        let runeHost = HostServicesImpl(appID: "rune", dataRootURL: pluginDataRoot,
                                            secretStore: secrets, themeManager: themeManager,
                                            hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                                            declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)
        TerminalSettingsMigration.runIfNeeded(
            legacyRawPayload: { (persistence as? FileDocumentStore)?.rawPayloadData(forID: $0) },
            scoped: runeHost.documents, defaults: defaults)

        // Sage is a host-embedded built-in (its views read `AppEnvironment`
        // directly), scoped like any other app for its documents/secrets/theme/context.
        let sageHost = HostServicesImpl(appID: "sage", dataRootURL: pluginDataRoot,
                                             secretStore: secrets, themeManager: themeManager,
                                             hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                                             declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        // Live Scry (M7 Slice 7) is likewise a host-embedded built-in — its
        // pane reads `AppEnvironment.canvasStore` directly (see `ScryApp`).
        let scryHost = HostServicesImpl(appID: "scry", dataRootURL: pluginDataRoot,
                                          secretStore: secrets, themeManager: themeManager,
                                          hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                                          declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        // Hoard (M1) — a host-embedded built-in like Sage and Scry. It
        // inherits the host's unsandboxed filesystem access; its own views read
        // `AppEnvironment` directly.
        let hoardHost = HostServicesImpl(appID: "hoard", dataRootURL: pluginDataRoot,
                                         secretStore: secrets, themeManager: themeManager,
                                         hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub,
                                         declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        // Hoard' MCP server and agent context are built HERE, not in
        // `HoardApp`, for the same reason its settings are: the SDK entry
        // points are static and see only `HostServices`, while the server must
        // drive the live stores on `AppEnvironment`. Hoard is host-embedded, so
        // the host is entitled to wire it directly.
        var filesRegistration = RegisteredApp.builtIn(
            HoardApp.self,
            summary: "Browse, search and organise your files — keyboard-driven, git-aware, and wired into the assistant.",
            host: hoardHost,
            chromeFillOverride: {
                HoardApp.surfaceFill(
                    opacity: appAppearanceStore.surfaceOpacity("hoard"),
                    base: themeManager.tokens.background
                )
            })
        filesRegistration.mcpServerFactory = { [weak environment] in
            guard let environment else { return MCPAppServer(appID: HoardApp.id) }
            return HoardMCPServer.make(environment: environment)
        }

        // Publish what the user is looking at, so the assistant has the
        // browser's state without having to ask for it.
        _ = hoardHost.context.register { [weak environment] in
            guard let environment,
                  let summary = environment.filesPaneCoordinator.contextSummary else { return nil }
            return AgentContextSnapshot(
                kind: "hoard", title: "Hoard", text: summary)
        }

        let loaded = loader.loadAll(from: pluginDirs)
        registry.install(
            builtIn: [
                RegisteredApp.builtIn(
                    SageApp.self,
                    summary: "Your in-workspace AI assistant — chat about your code, run gated tools, and drive the terminal and git without leaving Ainkrad.",
                    host: sageHost,
                    // Reading `surfaceOpacity` inside this closure — invoked
                    // synchronously from `TileLayoutView.hasTranslucentPane`
                    // and `BlockView.headerBackground` during their view
                    // bodies — registers an @Observable dependency, so dialing
                    // the slider live re-evaluates the backdrop + header.
                    chromeFillOverride: {
                        SageApp.surfaceFill(
                            opacity: appAppearanceStore.surfaceOpacity("sage"),
                            base: themeManager.tokens.background
                        )
                    }
                ),
                RegisteredApp.builtIn(
                    ScryApp.self,
                    summary: "The Live Scry — the assistant lays out tables, diagrams, charts, code and status as movable HUD cards.",
                    host: scryHost),
                filesRegistration
            ],
            loaded: loaded.apps,
            failures: loaded.failures
        )

        // App-hosted MCP servers (M9): `registry.install` above is the FIRST
        // moment any `RegisteredApp` — and therefore any `mcpServerFactory` —
        // exists, so discovery has to run here rather than beside the
        // `MCPServerRegistry` construction in `bootstrapExecutionAndTools`
        // (where the registry object exists but holds no apps yet). This call
        // itself is purely static and synchronous — it reads a nullable closure
        // per app, opens nothing and awaits nothing. (The `connectEnabled()`
        // below is the part with real cost, and it is deliberately off the
        // launch path; it does NOT open apps, because `AppServerActivator`
        // force-opens only for `tools/call`/`resources/read`.)
        AppMCPDiscovery.refresh(apps: registry.allApps, into: mcpServerRegistry.configStore)

        // Connect enabled MCP servers off the launch path: `connectEnabled()` is async
        // and per-server bounded/degrade-don't-crash (see `MCPServerRegistry`), but
        // launch itself must never block on a slow or down server, so this is fired
        // from an unawaited `Task` rather than run synchronously in `bootstrap()`.
        // Tools/trust populate as servers come up; a down server just never appears.
        // MUST stay below `AppMCPDiscovery.refresh` above: it connects whatever configs
        // exist at that moment, so app-server configs have to be synthesized first.
        // Skipped under a hosted test run for the same reason as the block above.
        if !AppEnvironment.isRunningUnderTests {
            Task { [weak mcpServerRegistry] in
                await mcpServerRegistry?.connectEnabled()
            }
        }

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

        // Counterpart to the open handler, for callers that need a live shell
        // rather than a launch — currently the app-hosted MCP activator, which
        // must not re-launch (and then time out waiting for) an app that is
        // already up. Installed here, with the same `[weak environment]` late
        // binding as the two handlers around it, because `presentedOverlayAppID`
        // only exists once `environment` does.
        pluginLaunchHub.setOpenStateProvider { [weak environment] appID in
            environment?.isAppOpen(appID) ?? false
        }

        // Generation 8: lets `apps.openReportingOutcome` tell a plugin WHY a
        // launch didn't happen. Leyline's "connect" used to look identical
        // whether Terminal opened or was never installed.
        pluginLaunchHub.setAvailabilityProvider { [weak environment] appID in
            guard let environment else { return .available }
            guard environment.registry.allApps.contains(where: { $0.id == appID }) else { return .unknown }
            return environment.registry.isEnabled(appID) ? .available : .disabled
        }

        Log.app.info("AppEnvironment bootstrapped with \(registry.allApps.count) registered app(s)")
    }
}
