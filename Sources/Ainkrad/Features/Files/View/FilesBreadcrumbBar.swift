import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// Breadcrumb that becomes a path editor on ⌘L. Two modes rather than an
/// always-editable field: the breadcrumb is the common case and clicking a
/// segment must navigate, not place a cursor.
struct FilesBreadcrumbBar: View {
    @Bindable var tab: FilesTab
    let fileSystem: any FileSystemServing

    @Binding var isEditing: Bool
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        Group {
            if isEditing { editor } else { breadcrumb }
        }
        .padding(.horizontal, FilesColumnMetrics.headerInset)
        .padding(.vertical, AinkradSpacing.sm)
        .onChange(of: isEditing) { _, editing in
            if editing {
                draft = tab.currentDirectory.path
                fieldFocused = true
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: AinkradSpacing.xs) {
            ForEach(Array(breadcrumbComponents(for: tab.currentDirectory).enumerated()), id: \.offset) { index, part in
                Button(part.name) { tab.navigate(to: part.url) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.foreground.opacity(0.75))
                // No chevron after the last segment — a trailing separator
                // pointing at nothing reads as a truncated path.
                if index < breadcrumbComponents(for: tab.currentDirectory).count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(theme.foreground.opacity(0.3))
                }
            }
            Spacer()
        }
        .font(.callout)
        .contentShape(Rectangle())
        .onTapGesture { isEditing = true }
    }

    private var editor: some View {
        TextField("Path", text: $draft)
            .textFieldStyle(.plain)
            .font(.callout.monospaced())
            .focused($fieldFocused)
            .onSubmit(commit)
            .onExitCommand { isEditing = false }
            .onKeyPress(.tab) {
                if let completed = completePath(draft, using: fileSystem,
                                                home: fileSystem.homeDirectory) {
                    draft = completed
                }
                return .handled
            }
    }

    private func commit() {
        let path = expandTilde(draft, home: fileSystem.homeDirectory)
        let url = URL(fileURLWithPath: path)
        // Typing a FILE path navigates to its enclosing folder — the useful
        // interpretation of pasting a path you copied from somewhere else.
        tab.navigate(to: fileSystem.isDirectory(url) ? url : url.deletingLastPathComponent())
        isEditing = false
    }
}
