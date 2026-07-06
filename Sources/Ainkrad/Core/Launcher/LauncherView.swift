import SwiftUI
import AppKit

/// Four corner brackets — the targeting-cursor treatment for the selected
/// Launcher row.
struct TargetingBrackets: Shape {
    var length: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

/// The ⌘K summon: the workspace behind dims and blurs (see RootView), and
/// a glowing command deck floats above it — command field, Spotlight-style
/// app rows with the neon tile artwork, targeting brackets on the
/// selection. Apps only: workspace management lives on its own surface.
struct LauncherView: View {
    /// Plain value snapshot of an app's display fields — iterating SwiftUI
    /// containers over `BuiltInApp.Type` metatypes crashes the Xcode 27
    /// beta SILGen (same workaround as BuiltInAppsSettingsView).
    private struct AppRow: Identifiable {
        let id: String
        let displayName: String
        let icon: String
    }

    @Environment(AppEnvironment.self) private var environment
    @Bindable var store: LauncherStore
    let onDismiss: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex = 0

    /// Sentinel id for the Settings entry — Settings is a summonable overlay,
    /// not a registered app, so it rides in the results as a system action.
    private static let settingsRowID = "settings"
    private static let marketplaceRowID = "marketplace"

    private var appRows: [AppRow] {
        var rows = store.appResults.map { AppRow(id: $0.id, displayName: $0.displayName, icon: $0.icon) }
        if store.query.isEmpty || fuzzyMatches(query: store.query, target: "Settings") {
            rows.append(AppRow(id: Self.settingsRowID, displayName: "Settings", icon: "gearshape"))
        }
        if store.query.isEmpty || fuzzyMatches(query: store.query, target: "Marketplace") {
            rows.append(AppRow(id: Self.marketplaceRowID, displayName: "Marketplace", icon: "bag"))
        }
        return rows
    }

    var body: some View {
        let tokens = environment.themeManager.tokens
        let results = appRows

        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                panel(results: results, tokens: tokens)
                    .frame(width: min(max(680, geo.size.width * 0.55), 820))
                    .offset(y: -60)
            }
        }
        .onAppear { isSearchFocused = true }
    }

    private func panel(results: [AppRow], tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            commandField(results: results, tokens: tokens)

            LinearGradient(
                colors: [.clear, tokens.accentPrimary.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            Text("APPS")
                .font(AinkradFont.mono(9, weight: .medium))
                .kerning(2.5)
                .foregroundStyle(tokens.foreground.opacity(0.4))
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)

            if results.isEmpty {
                Text("No matching apps")
                    .font(AinkradFont.display(13))
                    .foregroundStyle(tokens.foreground.opacity(0.35))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isSelected: index == selectedIndex, tokens: tokens)
                            .onTapGesture {
                                selectedIndex = index
                                select(results)
                            }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            footer(tokens: tokens)
        }
        .hudPanelChrome(tokens: tokens)
        .onChange(of: store.query) { _, _ in selectedIndex = 0 }
    }

    private func commandField(results: [AppRow], tokens: DesignTokens) -> some View {
        HStack(spacing: 12) {
            ChevronMark()
                .fill(tokens.accentSecondary)
                .frame(width: 16, height: 14)
                .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 6)

            TextField("Summon an app…", text: $store.query)
                .textFieldStyle(.plain)
                .font(AinkradFont.display(17))
                .foregroundStyle(tokens.foreground)
                .tint(tokens.accentSecondary)
                .focused($isSearchFocused)
                .onKeyPress(.escape) { dismiss(); return .handled }
                .onKeyPress(.downArrow) { move(by: 1, count: results.count); return .handled }
                .onKeyPress(.upArrow) { move(by: -1, count: results.count); return .handled }
                .onKeyPress(.return) { select(results); return .handled }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private func rowView(_ row: AppRow, isSelected: Bool, tokens: DesignTokens) -> some View {
        HStack(spacing: 12) {
            tile(for: row, tokens: tokens)

            Text(row.displayName)
                .font(AinkradFont.display(14, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(isSelected ? 1 : 0.75))

            Spacer()

            if isSelected {
                Text("↩")
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.accentSecondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? tokens.accentPrimary.opacity(0.14) : .clear)
        )
        .overlay(
            TargetingBrackets()
                .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.5)
                .padding(1)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: selectedIndex)
    }

    /// The app's neon tile artwork when bundled (Spotlight-style), else a
    /// themed mini-tile around its SF Symbol.
    @ViewBuilder
    private func tile(for row: AppRow, tokens: DesignTokens) -> some View {
        let assetName = "AppTile-\(row.id)-\(environment.themeManager.currentTheme.rawValue)"

        if NSImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(tokens.surfaceElevated)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: row.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(tokens.accentSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(tokens.accentPrimary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private func footer(tokens: DesignTokens) -> some View {
        HStack {
            Spacer()
            Text("↑↓ navigate    ↩ open    esc dismiss")
                .font(AinkradFont.mono(9))
                .kerning(0.5)
                .foregroundStyle(tokens.foreground.opacity(0.35))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func move(by delta: Int, count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func select(_ results: [AppRow]) {
        guard results.indices.contains(selectedIndex) else { return }
        let row = results[selectedIndex]

        if row.id == Self.settingsRowID {
            environment.isSettingsPresented = true
            dismiss()
            return
        }

        if row.id == Self.marketplaceRowID {
            environment.isMarketplacePresented = true
            dismiss()
            return
        }

        guard let app = store.appResults.first(where: { $0.id == row.id }) else { return }
        store.selectApp(app)
        dismiss()
    }

    private func dismiss() {
        store.query = ""
        selectedIndex = 0
        onDismiss()
    }
}
