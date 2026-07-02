import SwiftUI

/// The ⌘K overlay: a centered search field with Apps and Workspaces
/// sections below, fuzzy-filtered together as the user types. See
/// ADR-0008 App Launcher & Workspace Switching.
struct LauncherView: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var store: LauncherStore
    let onDismiss: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex = 0

    private enum Row {
        case app(BuiltInApp.Type)
        case workspace(LauncherWorkspaceResult)
    }

    private var rows: [Row] {
        store.appResults.map(Row.app) + store.workspaceResults.map(Row.workspace)
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            panel(tokens: tokens)
        }
        .onAppear { isSearchFocused = true }
    }

    private func panel(tokens: DesignTokens) -> some View {
        let currentRows = rows

        return VStack(alignment: .leading, spacing: 0) {
            TextField("Search apps…", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(tokens.foreground)
                .padding(12)
                .focused($isSearchFocused)
                .onKeyPress(.escape) { dismiss(); return .handled }
                .onKeyPress(.downArrow) { move(by: 1, count: currentRows.count); return .handled }
                .onKeyPress(.upArrow) { move(by: -1, count: currentRows.count); return .handled }
                .onKeyPress(.return) { select(currentRows); return .handled }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    section(title: "Apps", range: appRange(in: currentRows), rows: currentRows, tokens: tokens)
                    section(title: "Workspaces", range: workspaceRange(in: currentRows), rows: currentRows, tokens: tokens)
                }
                .padding(8)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 480)
        .background(tokens.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 24)
        .onChange(of: store.query) { _, _ in selectedIndex = 0 }
    }

    @ViewBuilder
    private func section(title: String, range: Range<Int>?, rows: [Row], tokens: DesignTokens) -> some View {
        if let range, !range.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.top, 6)

            ForEach(range, id: \.self) { index in
                rowView(rows[index], isSelected: index == selectedIndex, tokens: tokens)
                    .onTapGesture {
                        selectedIndex = index
                        select(rows)
                    }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, isSelected: Bool, tokens: DesignTokens) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: row))
                .foregroundStyle(tokens.accentPrimary)
                .frame(width: 16)
            Text(label(for: row))
                .foregroundStyle(tokens.foreground)
            Spacer()
            if case .workspace(.workspace(_, _, let isCurrent)) = row, isCurrent {
                Text("current")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? tokens.accentPrimary.opacity(0.18) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func icon(for row: Row) -> String {
        switch row {
        case .app(let app): return app.icon
        case .workspace(.workspace): return "square"
        case .workspace(.newWorkspace): return "plus.square"
        }
    }

    private func label(for row: Row) -> String {
        switch row {
        case .app(let app): return app.displayName
        case .workspace(.workspace(_, let label, _)): return label
        case .workspace(.newWorkspace): return "New Workspace"
        }
    }

    private func appRange(in rows: [Row]) -> Range<Int>? {
        let count = rows.filter { if case .app = $0 { return true } else { return false } }.count
        return count > 0 ? 0..<count : nil
    }

    private func workspaceRange(in rows: [Row]) -> Range<Int>? {
        let appCount = rows.filter { if case .app = $0 { return true } else { return false } }.count
        let workspaceCount = rows.count - appCount
        return workspaceCount > 0 ? appCount..<rows.count : nil
    }

    private func move(by delta: Int, count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func select(_ rows: [Row]) {
        guard rows.indices.contains(selectedIndex) else { return }
        switch rows[selectedIndex] {
        case .app(let app):
            store.selectApp(app)
        case .workspace(.workspace(let workspace, _, _)):
            store.selectWorkspace(workspace)
        case .workspace(.newWorkspace):
            store.selectNewWorkspace()
        }
        dismiss()
    }

    private func dismiss() {
        store.query = ""
        selectedIndex = 0
        onDismiss()
    }
}
