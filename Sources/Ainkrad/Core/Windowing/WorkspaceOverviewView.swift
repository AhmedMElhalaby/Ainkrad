import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The ⌥Tab Workspace Overview: the workspace counterpart of the ⌘K
/// Launcher, in the same visual language — blurred workspace behind, a
/// glowing panel of workspace cards. Each card shows the workspace's name
/// (double-click to rename), the app tiles inside it, and a delete control
/// (main is permanent). Cards drag-reorder; ⌘1-⌘9 follow the new order.
struct WorkspaceOverviewView: View {
    @Environment(AppEnvironment.self) private var environment
    let onDismiss: () -> Void

    @State private var selectedIndex = 0
    @State private var renamingWorkspaceID: UUID?
    @State private var renameDraft = ""
    @State private var draggedWorkspaceID: UUID?
    @State private var pendingDeletion: Workspace?
    @FocusState private var focus: FocusTarget?

    private enum FocusTarget: Hashable {
        case panel
        case rename(UUID)
    }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 12)]

    var body: some View {
        let tokens = environment.themeManager.tokens
        let workspaces = environment.workspaceManager.workspaces

        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            panel(workspaces: workspaces, tokens: tokens)
                .frame(width: 700)
                .offset(y: -40)
                .overlay {
                    if let pendingDeletion {
                        deleteConfirmation(pendingDeletion, tokens: tokens)
                            .offset(y: -40)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
        }
        .animation(.easeOut(duration: 0.14), value: pendingDeletion?.id)
        .onAppear {
            selectedIndex = workspaces.firstIndex(where: { $0.id == environment.workspaceManager.activeWorkspaceID }) ?? 0
            focus = .panel
        }
    }

    /// Themed confirmation shown only when deleting a workspace that still
    /// has apps open — an empty workspace deletes without ceremony.
    private func deleteConfirmation(_ workspace: Workspace, tokens: DesignTokens) -> some View {
        let appCount = workspace.tileLayout.appIDs.count

        return VStack(spacing: 14) {
            Text("Delete “\(workspace.name)”?")
                .font(AinkradFont.display(15, weight: .semibold))
                .foregroundStyle(tokens.foreground)
            Text("\(appCount) app\(appCount == 1 ? " is" : "s are") still open in it. Their sessions will end.")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    pendingDeletion = nil
                } label: {
                    Text("Cancel")
                        .font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.75))
                        .frame(width: 96, height: 30)
                        .background(tokens.surfaceElevated.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(tokens.accentPrimary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    confirmDeletion(workspace)
                } label: {
                    Text("Delete")
                        .font(AinkradFont.display(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 30)
                        .background(Color(hex: "E5484D").opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color(hex: "E5484D"), lineWidth: 1)
                        )
                        .shadow(color: Color(hex: "E5484D").opacity(0.5), radius: 10)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 340)
        .background(tokens.background.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [tokens.accentSecondary.opacity(0.5), tokens.accentPrimary.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 26, y: 8)
    }

    private func confirmDeletion(_ workspace: Workspace) {
        environment.workspaceManager.deleteWorkspace(workspace.id)
        selectedIndex = min(selectedIndex, environment.workspaceManager.workspaces.count - 1)
        pendingDeletion = nil
    }

    /// Empty workspaces delete immediately; ones with open apps confirm.
    private func requestDeletion(_ workspace: Workspace) {
        if workspace.tileLayout.appIDs.isEmpty {
            environment.workspaceManager.deleteWorkspace(workspace.id)
            selectedIndex = min(selectedIndex, environment.workspaceManager.workspaces.count - 1)
        } else {
            pendingDeletion = workspace
        }
    }

    private func panel(workspaces: [Workspace], tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ChevronMark()
                    .fill(tokens.accentSecondary)
                    .frame(width: 16, height: 14)
                    .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 6)
                Text("WORKSPACES")
                    .font(AinkradFont.display(13, weight: .semibold))
                    .kerning(4)
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                Spacer()
                Text("\(workspaces.count)")
                    .font(AinkradFont.mono(11, weight: .medium))
                    .foregroundStyle(tokens.accentSecondary.opacity(0.8))
            }
            .padding(.horizontal, 18)
            .frame(height: 52)

            LinearGradient(
                colors: [.clear, tokens.accentPrimary.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                        card(workspace, index: index, tokens: tokens)
                    }
                    newWorkspaceCard(tokens: tokens)
                }
                .padding(14)
            }
            .frame(maxHeight: 380)

            footer(tokens: tokens)
        }
        .background(tokens.background.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [tokens.accentSecondary.opacity(0.55), tokens.accentPrimary.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: tokens.accentPrimary.opacity(0.35), radius: 42)
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .focusable()
        .focused($focus, equals: .panel)
        .focusEffectDisabled()
        // While a rename field or the delete confirmation is active, the
        // panel's keys stand down: Return/Escape belong to that surface
        // (TextField commit/cancel, confirmation default/cancel actions).
        .onKeyPress(.escape) {
            if pendingDeletion != nil { pendingDeletion = nil; return .handled }
            guard renamingWorkspaceID == nil else { return .ignored }
            onDismiss(); return .handled
        }
        .onKeyPress(.rightArrow) {
            guard renamingWorkspaceID == nil, pendingDeletion == nil else { return .ignored }
            moveSelection(by: 1); return .handled
        }
        .onKeyPress(.leftArrow) {
            guard renamingWorkspaceID == nil, pendingDeletion == nil else { return .ignored }
            moveSelection(by: -1); return .handled
        }
        .onKeyPress(.return) {
            if let pendingDeletion {
                confirmDeletion(pendingDeletion)
                return .handled
            }
            guard renamingWorkspaceID == nil else { return .ignored }
            activateSelection(); return .handled
        }
        .onKeyPress(.deleteForward) {
            guard renamingWorkspaceID == nil, pendingDeletion == nil else { return .ignored }
            deleteSelection(); return .handled
        }
    }

    // MARK: - Cards

    private func card(_ workspace: Workspace, index: Int, tokens: DesignTokens) -> some View {
        let isActive = workspace.id == environment.workspaceManager.activeWorkspaceID
        let isSelected = index == selectedIndex
        let appIDs = workspace.tileLayout.appIDs

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if workspace.isMain {
                    ChevronMark()
                        .fill(tokens.accentSecondary)
                        .frame(width: 11, height: 9)
                }

                if renamingWorkspaceID == workspace.id {
                    TextField("Name", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground)
                        .focused($focus, equals: .rename(workspace.id))
                        .onSubmit { commitRename(workspace) }
                        .onKeyPress(.escape) { cancelRename(); return .handled }
                } else {
                    Text(workspace.name)
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(isActive ? 1 : 0.8))
                        .lineLimit(1)
                }

                Spacer()

                if !workspace.isMain {
                    Button {
                        requestDeletion(workspace)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tokens.foreground.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .help("Delete \(workspace.name)")
                }
            }

            appTiles(appIDs, tokens: tokens)

            HStack {
                if isActive {
                    Text("ACTIVE")
                        .font(AinkradFont.mono(8, weight: .medium))
                        .kerning(1.5)
                        .foregroundStyle(tokens.accentSecondary.opacity(0.9))
                }
                Spacer()
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(AinkradFont.mono(9))
                        .foregroundStyle(tokens.foreground.opacity(0.35))
                }
            }
        }
        .padding(12)
        .frame(height: 108)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? tokens.accentPrimary.opacity(0.13) : tokens.surface.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tokens.accentPrimary.opacity(isActive ? 0.4 : 0.15), lineWidth: 1)
        )
        .overlay(
            TargetingBrackets()
                .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.5)
                .padding(1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRename(workspace) }
        .onTapGesture {
            selectedIndex = index
            activateSelection()
        }
        .onDrag {
            draggedWorkspaceID = workspace.id
            return NSItemProvider(object: workspace.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: WorkspaceDropDelegate(
            target: workspace.id,
            dragged: $draggedWorkspaceID,
            manager: environment.workspaceManager
        ))
        .animation(.easeOut(duration: 0.12), value: selectedIndex)
    }

    private func appTiles(_ appIDs: [String], tokens: DesignTokens) -> some View {
        HStack(spacing: 5) {
            if appIDs.isEmpty {
                Text("Empty")
                    .font(AinkradFont.display(10))
                    .foregroundStyle(tokens.foreground.opacity(0.3))
            } else {
                ForEach(Array(appIDs.prefix(6).enumerated()), id: \.offset) { _, appID in
                    miniTile(appID, tokens: tokens)
                }
                if appIDs.count > 6 {
                    Text("+\(appIDs.count - 6)")
                        .font(AinkradFont.mono(9))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
            }
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private func miniTile(_ appID: String, tokens: DesignTokens) -> some View {
        let assetName = "AppTile-\(appID)-\(environment.themeManager.currentTheme.rawValue)"

        if NSImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(tokens.surfaceElevated)
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: environment.registry.allApps.first(where: { $0.id == appID })?.icon ?? "app")
                        .font(.system(size: 10))
                        .foregroundStyle(tokens.accentSecondary)
                )
        }
    }

    private func newWorkspaceCard(tokens: DesignTokens) -> some View {
        Button {
            environment.workspaceManager.createWorkspace()
            onDismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tokens.accentSecondary)
                Text("New Workspace")
                    .font(AinkradFont.display(11, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                Text("⌘⇧N")
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.35))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tokens.surface.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tokens.accentPrimary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footer(tokens: DesignTokens) -> some View {
        HStack {
            Text("drag to reorder    double-click to rename")
                .font(AinkradFont.mono(9))
                .kerning(0.5)
                .foregroundStyle(tokens.foreground.opacity(0.35))
            Spacer()
            Text("←→ navigate    ↩ switch    ⌦ delete    esc dismiss")
                .font(AinkradFont.mono(9))
                .kerning(0.5)
                .foregroundStyle(tokens.foreground.opacity(0.35))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        let count = environment.workspaceManager.workspaces.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func activateSelection() {
        let workspaces = environment.workspaceManager.workspaces
        guard workspaces.indices.contains(selectedIndex) else { return }
        environment.workspaceManager.switchTo(workspaces[selectedIndex].id)
        NSApp.keyWindow?.makeFirstResponder(nil)
        onDismiss()
    }

    private func deleteSelection() {
        let workspaces = environment.workspaceManager.workspaces
        guard workspaces.indices.contains(selectedIndex), !workspaces[selectedIndex].isMain else { return }
        requestDeletion(workspaces[selectedIndex])
    }

    private func beginRename(_ workspace: Workspace) {
        renameDraft = workspace.name
        renamingWorkspaceID = workspace.id
        focus = .rename(workspace.id)
    }

    private func commitRename(_ workspace: Workspace) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            workspace.name = trimmed
        }
        renamingWorkspaceID = nil
        focus = .panel
    }

    private func cancelRename() {
        renamingWorkspaceID = nil
        focus = .panel
    }
}

/// Reorders workspaces as a dragged card passes over its siblings, macOS
/// drag-and-drop grid style.
private struct WorkspaceDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragged: UUID?
    let manager: WorkspaceManager

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target,
              let from = manager.workspaces.firstIndex(where: { $0.id == dragged }),
              let to = manager.workspaces.firstIndex(where: { $0.id == target }) else { return }
        manager.moveWorkspace(
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
