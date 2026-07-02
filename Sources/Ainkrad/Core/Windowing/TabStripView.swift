import SwiftUI
import UniformTypeIdentifiers

/// The workspace's tab strip: slim chips under the HUD — click to switch,
/// double-click to rename, × to close, drag to reorder, + to create.
/// Hidden on the main workspace (the home island has no tabs).
struct TabStripView: View {
    @Environment(AppEnvironment.self) private var environment
    let workspace: Workspace

    @State private var renamingTabID: UUID?
    @State private var renameDraft = ""
    @State private var draggedTabID: UUID?
    @FocusState private var renameFocused: Bool

    var body: some View {
        let tokens = environment.themeManager.tokens

        HStack(spacing: 6) {
            ForEach(workspace.tabs) { tab in
                chip(tab, tokens: tokens)
            }

            Button {
                workspace.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New WorkspaceTab (⌘T)")

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .animation(.easeOut(duration: 0.15), value: workspace.tabs.map { $0.id })
    }

    private func chip(_ tab: WorkspaceTab, tokens: DesignTokens) -> some View {
        let isActive = tab.id == workspace.selectedTabID
        let index = workspace.tabs.firstIndex(where: { $0.id == tab.id }) ?? 0

        return HStack(spacing: 6) {
            if renamingTabID == tab.id {
                TextField("Name", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(AinkradFont.display(11, weight: .medium))
                    .foregroundStyle(tokens.foreground)
                    .frame(width: 90)
                    .focused($renameFocused)
                    .onSubmit { commitRename(tab) }
                    .onKeyPress(.escape) { renamingTabID = nil; return .handled }
            } else {
                Text(tab.name)
                    .font(AinkradFont.display(11, weight: .medium))
                    .kerning(0.4)
                    .foregroundStyle(tokens.foreground.opacity(isActive ? 0.95 : 0.5))
                    .lineLimit(1)
            }

            if workspace.tabs.count > 1 {
                Button {
                    workspace.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(tokens.foreground.opacity(isActive ? 0.55 : 0.3))
                }
                .buttonStyle(.plain)
                .help("Close WorkspaceTab")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? tokens.surfaceElevated.opacity(0.9) : tokens.surface.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? tokens.accentPrimary.opacity(0.5) : tokens.foreground.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if isActive {
                LinearGradient(
                    colors: [.clear, tokens.accentSecondary.opacity(0.9), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.horizontal, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRename(tab) }
        .onTapGesture { workspace.selectTab(tab.id) }
        .contextMenu {
            Button("Rename…") { beginRename(tab) }
            Button("Duplicate") { workspace.duplicateTab(tab.id) }
            if workspace.tabs.count > 1 {
                Divider()
                Button("Close WorkspaceTab", role: .destructive) { workspace.closeTab(tab.id) }
            }
        }
        .onDrag {
            draggedTabID = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: TabReorderDropDelegate(
            target: tab.id,
            dragged: $draggedTabID,
            workspace: workspace
        ))
        .help("Tab \(index + 1)\(index < 9 ? " — ⌘\(index + 1)" : "")")
    }

    private func beginRename(_ tab: WorkspaceTab) {
        renameDraft = tab.name
        renamingTabID = tab.id
        renameFocused = true
    }

    private func commitRename(_ tab: WorkspaceTab) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            tab.name = trimmed
            environment.workspaceManager.persist()
        }
        renamingTabID = nil
    }
}

private struct TabReorderDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragged: UUID?
    let workspace: Workspace

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target,
              let from = workspace.tabs.firstIndex(where: { $0.id == dragged }),
              let to = workspace.tabs.firstIndex(where: { $0.id == target }) else { return }
        workspace.moveTab(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to
        )
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
