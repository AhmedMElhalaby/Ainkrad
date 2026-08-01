import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The Files pane. M1 composition: sidebar + main column. This file stays a
/// thin composition root — everything with behaviour lives in its children.
struct FilesRootView: View {
    var body: some View {
        AinkradEmptyState(
            icon: "folder",
            title: "Files",
            message: "The file browser will appear here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
