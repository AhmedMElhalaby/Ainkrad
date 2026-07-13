import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The ⌥Tab Workspace Overview — a master–detail workspace manager in the HUD
/// language. Left: the workspace list (mini layout previews, rename, reorder,
/// delete) that doubles as drop targets. Right: the selected workspace's apps,
/// each openable, duplicable, closable, and draggable onto a workspace in the
/// list to move it there.
struct WorkspaceOverviewView: View {
    @Environment(AppEnvironment.self) private var environment
    let onDismiss: () -> Void

    @State private var selectedWorkspaceID: UUID?
    @State private var renamingWorkspaceID: UUID?
    @State private var renameDraft = ""
    @State private var draggedWorkspaceID: UUID?
    @State private var draggedApp: DraggedApp?
    @State private var pendingDeletion: Workspace?
    @FocusState private var focus: FocusTarget?

    /// A pane being dragged from the detail pane onto a workspace (to move it).
    struct DraggedApp: Equatable {
        let blockID: UUID
        let sourceWorkspaceID: UUID
    }

    private enum FocusTarget: Hashable {
        case panel
        case rename(UUID)
    }

    private var manager: WorkspaceManager { environment.workspaceManager }

    var body: some View {
        let tokens = environment.themeManager.tokens

        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                panel(tokens: tokens)
                    .frame(width: min(max(820, geo.size.width * 0.66), 1060),
                           height: min(max(520, geo.size.height * 0.8), 720))
                    .offset(y: -24)
                    .overlay {
                        if let pendingDeletion {
                            ZStack {
                                RoundedRectangle(cornerRadius: OverlayChrome.cornerRadius)
                                    .fill(.black.opacity(0.5))
                                    .transition(.opacity)
                                DeleteWorkspaceConfirmation(
                                    workspaceName: pendingDeletion.name,
                                    appCount: pendingDeletion.tileLayout.appIDs.count,
                                    tokens: tokens,
                                    onCancel: { self.pendingDeletion = nil },
                                    onConfirm: { confirmDeletion(pendingDeletion) }
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.16), value: pendingDeletion?.id)
        .onAppear {
            selectedWorkspaceID = manager.activeWorkspaceID
            focus = .panel
        }
    }

    // MARK: - Panel

    private func panel(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(tokens: tokens)
            horizontalRule(tokens: tokens)
            HStack(spacing: 0) {
                workspaceList(tokens: tokens)
                    .frame(width: 250)
                verticalRule(tokens: tokens)
                detailPane(tokens: tokens)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer(tokens: tokens)
        }
        .hudPanelChrome(tokens: tokens)
        .focusable()
        .focused($focus, equals: .panel)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            if pendingDeletion != nil { pendingDeletion = nil; return .handled }
            guard renamingWorkspaceID == nil else { return .ignored }
            onDismiss(); return .handled
        }
        .onKeyPress(.downArrow) { guard canNavigate else { return .ignored }; moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { guard canNavigate else { return .ignored }; moveSelection(by: -1); return .handled }
        .onKeyPress(.return) {
            if let pendingDeletion { confirmDeletion(pendingDeletion); return .handled }
            guard renamingWorkspaceID == nil else { return .ignored }
            activateSelection(); return .handled
        }
        .onKeyPress(.deleteForward) {
            guard canNavigate, let ws = selectedWorkspace, !ws.isMain else { return .ignored }
            requestDeletion(ws); return .handled
        }
    }

    private var canNavigate: Bool { renamingWorkspaceID == nil && pendingDeletion == nil }

    private func header(tokens: DesignTokens) -> some View {
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
            Text("\(manager.workspaces.count)")
                .font(AinkradFont.mono(11, weight: .medium))
                .foregroundStyle(tokens.accentSecondary.opacity(0.8))
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private func horizontalRule(tokens: DesignTokens) -> some View {
        LinearGradient(colors: [.clear, tokens.accentPrimary.opacity(0.5), .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
    }

    private func verticalRule(tokens: DesignTokens) -> some View {
        LinearGradient(colors: [.clear, tokens.accentPrimary.opacity(0.35), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: 1)
    }

    // MARK: - Workspace list (master)

    private func workspaceList(tokens: DesignTokens) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(manager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    workspaceRow(workspace, index: index, tokens: tokens)
                }
                newWorkspaceButton(tokens: tokens)
            }
            .padding(10)
        }
    }

    private func workspaceRow(_ workspace: Workspace, index: Int, tokens: DesignTokens) -> some View {
        let isActive = workspace.id == manager.activeWorkspaceID
        let isSelected = workspace.id == selectedWorkspaceID
        let isDropTarget = draggedApp != nil && draggedApp?.sourceWorkspaceID != workspace.id

        return HStack(spacing: 10) {
            LayoutThumbnail(layout: workspace.tileLayout, tokens: tokens)
                .frame(width: 42, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                if renamingWorkspaceID == workspace.id {
                    TextField("Name", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.foreground)
                        .focused($focus, equals: .rename(workspace.id))
                        .onSubmit { commitRename(workspace) }
                        .onKeyPress(.escape) { cancelRename(); return .handled }
                } else {
                    HStack(spacing: 5) {
                        if workspace.isMain {
                            ChevronMark().fill(tokens.accentSecondary).frame(width: 9, height: 7)
                        }
                        Text(workspace.name)
                            .font(AinkradFont.display(12, weight: .medium))
                            .foregroundStyle(tokens.foreground.opacity(isSelected || isActive ? 1 : 0.8))
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text(workspace.tileLayout.appIDs.isEmpty ? "empty" : "\(workspace.tileLayout.appIDs.count) app\(workspace.tileLayout.appIDs.count == 1 ? "" : "s")")
                        .font(AinkradFont.mono(8))
                        .foregroundStyle(tokens.foreground.opacity(0.4))
                    if isActive {
                        Text("ACTIVE").font(AinkradFont.mono(8, weight: .medium)).kerning(1)
                            .foregroundStyle(tokens.accentSecondary.opacity(0.9))
                    }
                }
            }
            Spacer(minLength: 4)

            if index < 9 {
                Text("⌘\(index + 1)").font(AinkradFont.mono(9)).foregroundStyle(tokens.foreground.opacity(0.3))
            }
            if !workspace.isMain {
                Button { requestDeletion(workspace) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tokens.foreground.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Delete \(workspace.name)")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? tokens.accentPrimary.opacity(0.14)
                      : (isActive ? tokens.accentPrimary.opacity(0.06) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isDropTarget ? tokens.accentSecondary.opacity(0.9)
                              : (isSelected ? tokens.accentPrimary.opacity(0.4) : .clear),
                              lineWidth: isDropTarget ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRename(workspace) }
        .onTapGesture { selectedWorkspaceID = workspace.id }
        .onDrag {
            draggedWorkspaceID = workspace.id
            return NSItemProvider(object: workspace.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: WorkspaceRowDropDelegate(
            target: workspace.id,
            draggedWorkspace: $draggedWorkspaceID,
            draggedApp: $draggedApp,
            manager: manager
        ))
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private func newWorkspaceButton(tokens: DesignTokens) -> some View {
        Button {
            let workspace = manager.createWorkspace()
            selectedWorkspaceID = workspace.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(tokens.accentSecondary)
                Text("New Workspace").font(AinkradFont.display(11, weight: .medium)).foregroundStyle(tokens.foreground.opacity(0.6))
                Spacer()
                Text("⌘⇧N").font(AinkradFont.mono(9)).foregroundStyle(tokens.foreground.opacity(0.3))
            }
            .padding(.horizontal, 9).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tokens.accentPrimary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private func detailPane(tokens: DesignTokens) -> some View {
        if let workspace = selectedWorkspace {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text(workspace.name)
                        .font(AinkradFont.display(16, weight: .semibold))
                        .foregroundStyle(tokens.foreground)
                        .lineLimit(1)
                    if workspace.id == manager.activeWorkspaceID {
                        Text("ACTIVE").font(AinkradFont.mono(8, weight: .bold)).tracking(1)
                            .foregroundStyle(tokens.accentSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(tokens.accentSecondary.opacity(0.15)))
                    }
                    Spacer()
                    if workspace.id != manager.activeWorkspaceID {
                        accentButton("Open Workspace", icon: "arrow.up.forward.square", tokens: tokens) {
                            manager.switchTo(workspace.id); onDismiss()
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)

                appList(workspace, tokens: tokens)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.split.3x1").font(.system(size: 30, weight: .light))
                    .foregroundStyle(tokens.accentPrimary.opacity(0.5))
                Text("Select a workspace").font(AinkradFont.display(13)).foregroundStyle(tokens.foreground.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func appList(_ workspace: Workspace, tokens: DesignTokens) -> some View {
        let blocks = workspace.tileLayout.blocks
        if blocks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "square.dashed").font(.system(size: 26, weight: .light))
                    .foregroundStyle(tokens.foreground.opacity(0.3))
                Text("No apps in this workspace")
                    .font(AinkradFont.display(12)).foregroundStyle(tokens.foreground.opacity(0.4))
                Text("Drag an app here from another workspace, or open one from the Launcher.")
                    .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(blocks) { block in
                        appRow(block, workspace: workspace, tokens: tokens)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }

    private func appRow(_ block: Block, workspace: Workspace, tokens: DesignTokens) -> some View {
        let app = environment.registry.allApps.first(where: { $0.id == block.appID })
        let name = app?.displayName ?? block.appID
        let sourceLabel: String = {
            switch app?.source { case .plugin: return "Plugin"; case .builtIn: return "Built-in"; case .none: return "" }
        }()

        return HStack(spacing: 11) {
            appIcon(block.appID, tokens: tokens)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(AinkradFont.display(12, weight: .medium)).foregroundStyle(tokens.foreground.opacity(0.9)).lineLimit(1)
                Text(sourceLabel).font(AinkradFont.mono(9)).foregroundStyle(tokens.foreground.opacity(0.4))
            }
            Spacer(minLength: 6)

            rowButton("arrow.up.forward.app", help: "Open in \(workspace.name)", tokens: tokens) {
                manager.switchTo(workspace.id)
                workspace.tileLayout.focus(block.id)
                onDismiss()
            }
            Menu {
                ForEach(manager.workspaces) { destination in
                    Button("Duplicate to \(destination.name)") {
                        manager.duplicateApp(block.appID, to: destination.id)
                    }
                }
                Button("Duplicate to New Workspace") {
                    let destination = manager.createWorkspace()
                    manager.duplicateApp(block.appID, to: destination.id)
                }
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(tokens.surfaceElevated.opacity(0.5)))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Duplicate \(name) to another workspace")

            rowButton("xmark", help: "Close \(name)", tokens: tokens) {
                workspace.tileLayout.close(block.id)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tokens.surfaceElevated.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tokens.foreground.opacity(0.06)))
        .contentShape(Rectangle())
        .onDrag {
            draggedApp = DraggedApp(blockID: block.id, sourceWorkspaceID: workspace.id)
            return NSItemProvider(object: "appmove:\(block.id.uuidString)" as NSString)
        }
        .help("Drag onto a workspace on the left to move it")
    }

    private func rowButton(_ symbol: String, help: String, tokens: DesignTokens, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.55))
                .frame(width: 24, height: 24)
                .background(Circle().fill(tokens.surfaceElevated.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func accentButton(_ title: String, icon: String, tokens: DesignTokens, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(AinkradFont.display(12, weight: .medium))
            }
            .foregroundStyle(tokens.accentPrimary.contrastingText.opacity(0.95))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tokens.accentPrimary.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.accentSecondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    private func appIcon(_ appID: String, tokens: DesignTokens) -> some View {
        let symbol = environment.registry.allApps.first(where: { $0.id == appID })?.icon ?? "app"
        return NeonAppTile(symbol: symbol, tokens: tokens, size: 26)
    }

    private func footer(tokens: DesignTokens) -> some View {
        HStack {
            Text("drag an app onto a workspace to move it · double-click to rename · drag to reorder")
                .font(AinkradFont.mono(9)).kerning(0.5).foregroundStyle(tokens.foreground.opacity(0.35))
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            Text("↑↓ select   ↩ switch   ⌦ delete   esc dismiss")
                .font(AinkradFont.mono(9)).kerning(0.5).foregroundStyle(tokens.foreground.opacity(0.35))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    // MARK: - Actions

    private var selectedWorkspace: Workspace? {
        manager.workspaces.first { $0.id == selectedWorkspaceID }
    }

    private func moveSelection(by delta: Int) {
        let workspaces = manager.workspaces
        guard !workspaces.isEmpty else { return }
        let current = workspaces.firstIndex { $0.id == selectedWorkspaceID } ?? 0
        let next = (current + delta + workspaces.count) % workspaces.count
        selectedWorkspaceID = workspaces[next].id
    }

    private func activateSelection() {
        guard let workspace = selectedWorkspace else { return }
        manager.switchTo(workspace.id)
        NSApp.keyWindow?.makeFirstResponder(nil)
        onDismiss()
    }

    private func requestDeletion(_ workspace: Workspace) {
        if workspace.tileLayout.appIDs.isEmpty {
            deleteWorkspace(workspace)
        } else {
            pendingDeletion = workspace
        }
    }

    private func confirmDeletion(_ workspace: Workspace) {
        deleteWorkspace(workspace)
        pendingDeletion = nil
    }

    private func deleteWorkspace(_ workspace: Workspace) {
        let wasSelected = selectedWorkspaceID == workspace.id
        manager.deleteWorkspace(workspace.id)
        if wasSelected { selectedWorkspaceID = manager.activeWorkspaceID }
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
            manager.persist()
        }
        renamingWorkspaceID = nil
        focus = .panel
    }

    private func cancelRename() {
        renamingWorkspaceID = nil
        focus = .panel
    }
}

/// A tiny thumbnail of a workspace's pane arrangement, drawn from the layout's
/// unit-space pane frames.
private struct LayoutThumbnail: View {
    let layout: TileLayout
    let tokens: DesignTokens

    var body: some View {
        let frames = layout.paneFrames()
        GeometryReader { geo in
            if frames.isEmpty {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(tokens.foreground.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(frames.keys), id: \.self) { id in
                        let rect = frames[id] ?? .zero
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tokens.accentPrimary.opacity(0.45))
                            .frame(width: max(2, rect.width * geo.size.width - 2),
                                   height: max(2, rect.height * geo.size.height - 2))
                            .offset(x: rect.minX * geo.size.width + 1, y: rect.minY * geo.size.height + 1)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tokens.surface.opacity(0.5)))
            }
        }
    }
}

/// A workspace row's drop target: dragging another workspace row reorders the
/// list; dropping an app dragged from the detail pane moves that app here.
private struct WorkspaceRowDropDelegate: DropDelegate {
    let target: UUID
    @Binding var draggedWorkspace: UUID?
    @Binding var draggedApp: WorkspaceOverviewView.DraggedApp?
    let manager: WorkspaceManager

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedWorkspace, dragged != target,
              let from = manager.workspaces.firstIndex(where: { $0.id == dragged }),
              let to = manager.workspaces.firstIndex(where: { $0.id == target }) else { return }
        manager.moveWorkspace(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        if let app = draggedApp, app.sourceWorkspaceID != target {
            manager.moveApp(app.blockID, from: app.sourceWorkspaceID, to: target)
        }
        draggedWorkspace = nil
        draggedApp = nil
        return true
    }
}

/// The delete-workspace confirmation, in the app's HUD language: a hazard
/// emblem inside targeting brackets, an energy-seam divider, and a glowing
/// destructive action. Shown only when the workspace still has apps open.
private struct DeleteWorkspaceConfirmation: View {
    let workspaceName: String
    let appCount: Int
    let tokens: DesignTokens
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var deleteHover = false
    @State private var cancelHover = false

    private let danger = Color(hex: "E5484D")

    var body: some View {
        VStack(spacing: 0) {
            emblem
                .padding(.top, 26)
                .padding(.bottom, 16)

            Text("Delete “\(workspaceName)”?")
                .font(AinkradFont.display(16, weight: .semibold))
                .foregroundStyle(tokens.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)

            Text("\(appCount) app\(appCount == 1 ? "" : "s") still running here — \(appCount == 1 ? "its session" : "their sessions") will end.")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 26)
                .padding(.top, 7)

            LinearGradient(colors: [.clear, danger.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .padding(.horizontal, 22)
                .padding(.top, 20)

            HStack(spacing: 10) {
                cancelButton
                deleteButton
            }
            .padding(20)
        }
        .frame(width: 360)
        .background(tokens.background.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(colors: [danger.opacity(0.55), tokens.accentPrimary.opacity(0.2)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .overlay(
            TargetingBrackets(length: 13)
                .stroke(danger.opacity(0.4), lineWidth: 1.5)
                .padding(-3)
        )
        .shadow(color: danger.opacity(0.28), radius: 30)
        .shadow(color: .black.opacity(0.55), radius: 24, y: 8)
    }

    private var emblem: some View {
        ZStack {
            Circle().fill(danger.opacity(0.12)).frame(width: 54, height: 54)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(danger)
                .shadow(color: danger.opacity(0.7), radius: 9)
        }
        .overlay(
            TargetingBrackets(length: 9)
                .stroke(danger.opacity(0.85), lineWidth: 1.3)
                .frame(width: 62, height: 62)
        )
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("Cancel")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(cancelHover ? 0.95 : 0.75))
                .frame(width: 108, height: 32)
                .background(tokens.surfaceElevated.opacity(cancelHover ? 0.95 : 0.75))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.accentPrimary.opacity(cancelHover ? 0.5 : 0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { cancelHover = $0 }
    }

    private var deleteButton: some View {
        Button(action: onConfirm) {
            Text("Delete")
                .font(AinkradFont.display(12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 108, height: 32)
                .background(danger.opacity(deleteHover ? 1 : 0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(danger, lineWidth: 1))
                .overlay(
                    TargetingBrackets(length: 8)
                        .stroke(deleteHover ? .white.opacity(0.9) : .clear, lineWidth: 1.3)
                        .padding(3)
                )
                .shadow(color: danger.opacity(deleteHover ? 0.75 : 0.45), radius: deleteHover ? 14 : 10)
        }
        .buttonStyle(.plain)
        .onHover { deleteHover = $0 }
        .animation(.easeOut(duration: 0.12), value: deleteHover)
    }
}
