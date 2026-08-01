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
    @State private var isEditingPath = false
    @State private var watcher: DirectoryWatcher?

    private let fileSystem = LocalFileSystemService()

    private var settings: FilesSettingsStore { environment.filesSettingsStore }

    var body: some View {
        Group {
            if let store {
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
                            showMetadata: settings.showMetadataColumns
                        )
                        FilesStatusBar(tab: store.activeTab)
                    }
                }
                .filesKeyboardHandling(store: store, isEditingPath: $isEditingPath)
                // One watcher, always pointed at whatever the active tab is
                // showing. Re-created on navigation and on tab switch, since
                // both change which directory matters.
                .onChange(of: store.activeTab.currentDirectory, initial: true) { _, directory in
                    watcher?.stop()
                    watcher = DirectoryWatcher(url: directory) { [weak store] in
                        store?.activeTab.reload()
                    }
                }
                .onDisappear {
                    watcher?.stop()
                    watcher = nil
                }
            } else {
                AinkradLoadingState(label: "Opening…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Files' own typography override, or the workspace default.
        .filesTypography(environment)
        .task {
            if store == nil {
                store = FilesPaneStore(fileSystem: fileSystem,
                                       persistence: environment.persistence)
            }
        }
    }
}
