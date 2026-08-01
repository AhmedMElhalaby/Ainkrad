import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The Files pane: sidebar beside a column of tab strip, breadcrumb, list and
/// status bar. Composition only — no behaviour lives here.
struct FilesRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: FilesPaneStore?
    @State private var isEditingPath = false

    private let fileSystem = LocalFileSystemService()

    var body: some View {
        Group {
            if let store {
                HStack(spacing: 0) {
                    FilesSidebar(
                        roots: standardRoots(home: fileSystem.homeDirectory),
                        currentDirectory: store.activeTab.currentDirectory,
                        onSelect: { store.activeTab.navigate(to: $0.url) }
                    )
                    VStack(spacing: 0) {
                        FilesTabStrip(store: store)
                        FilesBreadcrumbBar(tab: store.activeTab, fileSystem: fileSystem,
                                           isEditing: $isEditingPath)
                        FileListView(tab: store.activeTab)
                        FilesStatusBar(tab: store.activeTab)
                    }
                }
            } else {
                AinkradLoadingState(label: "Opening…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if store == nil {
                store = FilesPaneStore(fileSystem: fileSystem,
                                       persistence: environment.persistence)
            }
        }
    }
}
