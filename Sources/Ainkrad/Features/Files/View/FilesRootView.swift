import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The Files pane. M1 composition: sidebar + main column. This file stays a
/// thin composition root — everything with behaviour lives in its children.
struct FilesRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: FilesPaneStore?

    private let fileSystem = LocalFileSystemService()

    var body: some View {
        Group {
            if let store {
                FileListView(tab: store.activeTab)
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
