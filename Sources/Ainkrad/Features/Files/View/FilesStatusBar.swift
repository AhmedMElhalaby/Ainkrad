import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// Pane footer. Note this is a local view, NOT the kit's `AinkradStatusBar` —
/// that component is an HP-bar segmented gauge, a different thing entirely.
struct FilesStatusBar: View {
    let tab: FilesTab
    /// Enclosing repo, when there is one.
    let repoStatus: GitRepoStatus?

    var body: some View {
        HStack(spacing: AinkradSpacing.md) {
            AinkradCaption(selectionSummary(entries: tab.visibleEntries, selection: tab.selection))
            Spacer()
            if tab.showHidden {
                AinkradCaption("Hidden shown")
            }
            if let repoStatus {
                AinkradCaption("\(repoStatus.root.lastPathComponent) · \(repoStatus.branch ?? "—")")
            }
        }
        .padding(.horizontal, FilesColumnMetrics.headerInset)
        .padding(.vertical, AinkradSpacing.sm)
    }
}
