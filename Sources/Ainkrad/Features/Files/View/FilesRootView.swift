import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The Files pane: sidebar beside a column of tab strip, breadcrumb, list and
/// status bar. Composition only — no behaviour lives here.
///
/// Deliberately paints NO background of its own. The pane's fill comes from
/// `FilesApp.surfaceFill` via `RegisteredApp.chromeFill`, which is what lets a
/// translucent Files reveal the shared blurred island and keeps the title bar
/// the same colour and opacity as the body. Any opaque background here would
/// cover the island and break that continuity.
struct FilesRootView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var store: FilesPaneStore?
    @State private var actions: FilesActions?
    @State private var paneToken: UUID?
    @State private var resolver = ConflictResolver()
    @State private var isEditingPath = false
    @State private var watcher: DirectoryWatcher?
    @State private var toast: String?
    @State private var search: FilesSearchStore?

    private var settings: FilesSettingsStore { environment.filesSettingsStore }
    private var fileSystem: LocalFileSystemService { environment.filesSystemService }
    private var engine: FileOperationEngine { environment.filesOperationEngine }
    private var git: GitStatusProvider { environment.filesGitStatusProvider }

    var body: some View {
        Group {
            if let store, let actions {
                paneBody(store: store, actions: actions)
            } else {
                AinkradLoadingState(label: "Opening…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .filesTypography(environment)
        .task { activate() }
        .onDisappear(perform: deactivate)
    }

    private func paneBody(store: FilesPaneStore, actions: FilesActions) -> some View {
        HStack(spacing: 0) {
            FilesSidebar(
                roots: standardRoots(home: fileSystem.homeDirectory),
                currentDirectory: store.activeTab.currentDirectory,
                iconSize: CGFloat(settings.iconSize),
                rowPadding: settings.rowVerticalPadding,
                onSelect: { store.activeTab.navigate(to: $0.url) }
            )
            VStack(spacing: 0) {
                FilesTabStrip(store: store)
                FilesBreadcrumbBar(tab: store.activeTab, fileSystem: fileSystem,
                                   isEditing: $isEditingPath)
                FileListView(
                    tab: store.activeTab,
                    iconSize: CGFloat(settings.iconSize),
                    rowPadding: settings.rowVerticalPadding,
                    showMetadata: settings.showMetadataColumns,
                    filter: { search?.filtered($0) ?? $0 },
                    useGrid: settings.useGrid,
                    gitStatus: { git.status(for: $0) }
                )
                FilesStatusBar(
                    tab: store.activeTab,
                    repoStatus: git.status(forDirectory: store.activeTab.currentDirectory))
            }
            if settings.showPreview {
                PreviewPane(entry: store.activeTab.cursorEntry,
                            itemCount: store.activeTab.visibleEntries.count)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: settings.showPreview)
        .filesKeyboardHandling(
            store: store, actions: actions, undoStack: environment.filesUndoStack,
            onUndo: { if let refusal = engine.undo() { toast = refusal.message } },
            onRedo: { _ = engine.redo() },
            onTogglePreview: { settings.showPreview.toggle() },
            onOpenFinder: { mode in openFinder(mode, store: store) },
            isFinderOpen: search?.isActive ?? false,
            vimKeys: settings.vimKeys,
            isEditingPath: $isEditingPath)
        .overlay(alignment: .top) {
            if let search, search.isActive {
                FilesFinderBar(
                    search: search,
                    iconSize: CGFloat(settings.iconSize),
                    onSubmit: { hit in accept(hit, store: store) },
                    onRunSearch: { search.runSearch(root: store.activeTab.currentDirectory) },
                    onClose: { search.close() })
                    .padding(.top, AinkradSpacing.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            OperationsPanel(engine: engine).padding(AinkradSpacing.md)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                AinkradBanner(message: toast) { self.toast = nil }
                    .padding(AinkradSpacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // One watcher, always pointed at whatever the active tab is showing.
        .onChange(of: store.activeTab.currentDirectory, initial: true) { _, directory in
            watcher?.stop()
            watcher = DirectoryWatcher(url: directory) { [weak store] in
                store?.activeTab.reload()
                // The watcher's 200ms coalescing is what keeps a `git checkout`
                // from spawning hundreds of status refreshes.
                Task { await refreshGit(directory: directory, store: store) }
            }
            Task { await refreshGit(directory: directory, store: store) }
        }
        // The coordinator needs to know which pane was last touched, so F5 in
        // a three-pane workspace targets the one the user actually means.
        .onTapGesture {
            if let paneToken { environment.filesPaneCoordinator.noteFocus(paneToken) }
        }
        .onChange(of: actions.lastMessage) { _, message in
            if let message { toast = message; actions.clearMessage() }
        }
        .sheet(item: Binding(get: { actions.prompt },
                             set: { if $0 == nil { actions.present(nil) } })) { prompt in
            FilesPromptSheet(
                prompt: prompt,
                onCancel: { actions.present(nil) },
                onRename: { entry, name in Task { await actions.commitRename(entry, to: name) } },
                onNewFolder: { name in Task { await actions.commitNewFolder(named: name) } })
        }
        .sheet(isPresented: Binding(get: { resolver.pending != nil },
                                    set: { if !$0 { resolver.cancel() } })) {
            if let question = resolver.pending {
                ConflictSheet(question: question) { resolver.answer($0) }
            }
        }
        .animation(.easeOut(duration: 0.18), value: toast)
    }

    /// `/` and ⌘P work off data already in memory; ⌘F walks the disk, so it
    /// only starts when the user commits with Return.
    private func openFinder(_ mode: FilesFinderMode, store: FilesPaneStore) {
        let search = self.search ?? FilesSearchStore(fileSystem: fileSystem)
        self.search = search
        search.open(mode)
        if mode == .jump {
            search.loadJumpCandidates(root: store.activeTab.currentDirectory)
        }
    }

    private func accept(_ hit: SearchHit, store: FilesPaneStore) {
        let tab = store.activeTab
        if hit.entry.isDirectory {
            tab.navigate(to: hit.entry.url)
        } else {
            tab.navigate(to: hit.entry.url.deletingLastPathComponent())
            tab.select(matching: hit.entry.url)
        }
        search?.close()
    }

    private func activate() {
        guard store == nil else { return }
        let store = FilesPaneStore(fileSystem: fileSystem, persistence: environment.persistence)
        let token = environment.filesPaneCoordinator.register(store)
        self.store = store
        self.paneToken = token
        self.actions = FilesActions(
            engine: engine, coordinator: environment.filesPaneCoordinator,
            resolver: resolver, store: store, paneToken: token)
    }

    /// Fetches status if cold, then republishes the ignore set so the list can
    /// filter on it.
    private func refreshGit(directory: URL, store: FilesPaneStore?) async {
        await git.refreshIfNeeded(directory: directory)
        guard let store, let status = git.status(forDirectory: directory) else {
            store?.activeTab.ignoredURLs = []
            return
        }
        let ignored = status.entries
            .filter { $0.value == .ignored }
            .map { status.root.appendingPathComponent($0.key) }
        store.activeTab.ignoredURLs = Set(ignored)
    }

    private func deactivate() {
        watcher?.stop()
        watcher = nil
        // Deregister so a closed pane stops being a copy target. The
        // coordinator lives in `AppEnvironment` precisely so this is safe —
        // the surviving pane is unaffected.
        if let paneToken { environment.filesPaneCoordinator.deregister(paneToken) }
        paneToken = nil
    }
}
