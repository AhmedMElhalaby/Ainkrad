import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// Name entry for rename and new folder, plus the "only one pane open"
/// explanation. One file because they are the same shape — a short modal with
/// a field or a message — and splitting them would be three near-identical
/// files.
struct FilesPromptSheet: View {
    let prompt: FilesPrompt
    let onCancel: () -> Void
    let onRename: (FileEntry, String) -> Void
    let onNewFolder: (String) -> Void

    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            Text(title)
                .font(AinkradFontResolver.font(.headline, weight: .medium, typography: typo))
                .foregroundStyle(theme.foreground)

            switch prompt {
            case .rename, .newFolder:
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(AinkradFontResolver.font(.body, typography: typo))
                    .focused($fieldFocused)
                    .padding(.horizontal, AinkradSpacing.sm)
                    .padding(.vertical, 6)
                    .background(ChamferShape(cut: 4).fill(theme.foreground.opacity(0.08)))
                    .onSubmit(commit)

            case .noDestination(let isMove):
                Text("""
                     Open a second Files pane to \(isMove ? "move" : "copy") into. \
                     Files uses the workspace's own tiling for its second pane rather \
                     than splitting inside one.
                     """)
                    .font(AinkradFontResolver.font(.body, typography: typo))
                    .foregroundStyle(theme.foreground.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: AinkradSpacing.sm) {
                Spacer()
                AinkradButton(title: cancelTitle, style: .ghost, action: onCancel)
                if confirmTitle != nil {
                    AinkradButton(title: confirmTitle!, style: .primary, action: commit)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(AinkradSpacing.lg)
        .frame(width: 380)
        .onAppear {
            if case .rename(let entry) = prompt { text = entry.name }
            fieldFocused = true
        }
    }

    private var title: String {
        switch prompt {
        case .rename: return "Rename"
        case .newFolder: return "New Folder"
        case .noDestination(let isMove): return isMove ? "Nowhere to Move To" : "Nowhere to Copy To"
        }
    }

    private var placeholder: String {
        if case .newFolder = prompt { return "untitled folder" }
        return "Name"
    }

    private var cancelTitle: String {
        if case .noDestination = prompt { return "OK" }
        return "Cancel"
    }

    private var confirmTitle: String? {
        switch prompt {
        case .rename: return "Rename"
        case .newFolder: return "Create"
        case .noDestination: return nil
        }
    }

    private func commit() {
        switch prompt {
        case .rename(let entry): onRename(entry, text)
        case .newFolder: onNewFolder(text)
        case .noDestination: onCancel()
        }
    }
}

/// Replace / Keep both / Skip / Merge, with apply-to-all.
struct ConflictSheet: View {
    let question: ConflictQuestion
    let onAnswer: (ConflictAnswer) -> Void

    @State private var applyToAll = false

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            Text("“\(question.name)” already exists")
                .font(AinkradFontResolver.font(.headline, weight: .medium, typography: typo))
                .foregroundStyle(theme.foreground)

            Text(question.destination.deletingLastPathComponent().path)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(theme.foreground.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)

            // One decision for the whole batch — the reason a 200-file
            // conflict isn't 200 dialogs.
            Toggle("Apply to all remaining", isOn: $applyToAll)
                .toggleStyle(.switch)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(theme.foreground.opacity(0.75))

            HStack(spacing: AinkradSpacing.sm) {
                Spacer()
                AinkradButton(title: "Skip", style: .ghost) { answer(.skip) }
                AinkradButton(title: "Keep Both", style: .secondary) { answer(.keepBoth) }
                if question.isDirectory {
                    AinkradButton(title: "Merge", style: .secondary) { answer(.merge) }
                }
                AinkradButton(title: "Replace", style: .primary) { answer(.replace) }
            }
        }
        .padding(AinkradSpacing.lg)
        .frame(width: 460)
    }

    private func answer(_ policy: ConflictPolicy) {
        onAnswer(ConflictAnswer(policy: policy, applyToAll: applyToAll))
    }
}
