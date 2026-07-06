import SwiftUI

/// The App Store HUD overlay — browse the catalog and install / update /
/// uninstall / enable apps. Same HUD language as the Launcher / Settings.
struct AppStoreOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var store: AppStoreStore
    let onDismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        let tokens = environment.themeManager.tokens
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity).ignoresSafeArea().onTapGesture { onDismiss() }
                panel(tokens: tokens)
                    .frame(
                        width: min(max(900, geo.size.width * 0.82), 1120),
                        height: min(max(600, geo.size.height * 0.82), 760)
                    )
                    .offset(y: -30)
                if let id = store.pendingReinstall {
                    reinstallModal(appID: id, tokens: tokens)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.94).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: store.pendingReinstall)
        }
        .task { store.reloadRows() }
    }

    /// The retained-data Restore/Reset prompt shown when reinstalling an app
    /// that left settings behind — same HUD chrome as the rest of the
    /// overlay, with a scale/opacity entrance and pressable buttons (AIN-149).
    /// Skipped under Reduce Motion.
    private func reinstallModal(appID: String, tokens: DesignTokens) -> some View {
        let name = store.rows.first { $0.id == appID }?.displayName ?? appID
        return ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { store.cancelReinstall() }
            VStack(alignment: .leading, spacing: 14) {
                Text("Reinstall \(name)")
                    .font(AinkradFont.display(15, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                Text("Previous settings for \(name) were kept. Restore them, or reset to defaults?")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foreground.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { store.cancelReinstall() }
                        .buttonStyle(AppStorePressableButtonStyle(reduceMotion: reduceMotion))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                    Button("Reset to Defaults") { Task { await store.resetAndInstall(appID) } }
                        .buttonStyle(AppStorePressableButtonStyle(reduceMotion: reduceMotion))
                        .foregroundStyle(tokens.accentTertiary)
                    Button("Restore") { Task { await store.restoreAndInstall(appID) } }
                        .buttonStyle(AppStorePressableButtonStyle(reduceMotion: reduceMotion))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(tokens.accentPrimary.opacity(0.9)))
                        .foregroundStyle(tokens.background)
                }
            }
            .padding(20)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 12).fill(tokens.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tokens.accentPrimary.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        }
        .onKeyPress(.escape) { store.cancelReinstall(); return .handled }
    }

    private func panel(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let row = store.selectedRow {
                AppStoreDetailView(
                    entry: store.entry(for: row.id), row: row, tokens: tokens, isBusy: store.busy.contains(row.id),
                    onBack: { store.closeDetail() },
                    onInstall: { environment.sounds.play(.install); Task { await store.install(row.id) } },
                    onUpdate: { Task { await store.update(row.id) } },
                    onUninstall: { environment.sounds.play(.uninstall); store.uninstall(row.id) },
                    onToggleEnabled: { environment.sounds.play(.toggle); store.setEnabled($0, for: row.id) })
            } else {
                header(tokens: tokens)
                LinearGradient(colors: [.clear, tokens.accentPrimary.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                filterBar(tokens: tokens)
                content(tokens: tokens)
            }
        }
        .hudPanelChrome(tokens: tokens)
        .onKeyPress(.escape) {
            if store.selectedAppID != nil { store.closeDetail() } else { onDismiss() }
            return .handled
        }
    }

    private func header(tokens: DesignTokens) -> some View {
        HStack {
            Text("APP STORE").font(AinkradFont.display(14, weight: .semibold)).kerning(1)
                .foregroundStyle(tokens.foreground)
            Spacer()
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(tokens.foreground.opacity(0.7))
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
            }.buttonStyle(.plain).help("Refresh catalog")
            Button { onDismiss() } label: { Image(systemName: "xmark").foregroundStyle(tokens.foreground.opacity(0.6)) }
                .buttonStyle(.plain).help("Close")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private func filterBar(tokens: DesignTokens) -> some View {
        let updateCount = store.rows.filter { $0.status == .updateAvailable }.count
        return HStack(spacing: 8) {
            chip("All", .all, tokens: tokens)
            chip("Installed", .installed, tokens: tokens)
            chip(updateCount > 0 ? "Updates (\(updateCount))" : "Updates", .updates, tokens: tokens)
            searchField(tokens: tokens)
            Spacer()
            if let error = store.error {
                Text(errorText(error)).font(.system(size: 10)).foregroundStyle(tokens.accentTertiary)
                    .lineLimit(1)
                Button { store.error = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(tokens.foreground.opacity(0.4)) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    /// Live search over the visible rows (AIN-148) — name/description/author,
    /// case-insensitive, client-side. Composes with the filter chips above.
    private func searchField(tokens: DesignTokens) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(tokens.foreground.opacity(0.45))
            TextField("Search apps…", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground)
                .tint(tokens.accentPrimary)
            if !store.searchQuery.isEmpty {
                Button { store.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.foreground.opacity(0.4))
                }.buttonStyle(.plain).help("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(width: 200)
        .background(RoundedRectangle(cornerRadius: 7).fill(tokens.surface.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(tokens.foreground.opacity(0.1), lineWidth: 1))
    }

    private func chip(_ title: String, _ value: AppStoreStore.Filter, tokens: DesignTokens) -> some View {
        let selected = store.filter == value
        return Button { store.filter = value } label: {
            Text(title).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(selected ? tokens.accentPrimary.opacity(0.2) : tokens.surface.opacity(0.6)))
                .overlay(Capsule().strokeBorder(selected ? tokens.accentPrimary.opacity(0.5) : .clear, lineWidth: 1))
                .foregroundStyle(selected ? tokens.foreground : tokens.foreground.opacity(0.6))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func content(tokens: DesignTokens) -> some View {
        let rows = store.visibleRows
        if rows.isEmpty {
            VStack { Spacer(); Text(emptyText).font(.system(size: 13)).foregroundStyle(tokens.foreground.opacity(0.5)); Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(rows) { row in
                        AppStoreCard(
                            row: row, tokens: tokens, isBusy: store.busy.contains(row.id),
                            onOpen: { store.openDetail(row.id) },
                            onInstall: { environment.sounds.play(.install); Task { await store.install(row.id) } },
                            onUpdate: { Task { await store.update(row.id) } },
                            onUninstall: { environment.sounds.play(.uninstall); store.uninstall(row.id) },
                            onToggleEnabled: { environment.sounds.play(.toggle); store.setEnabled($0, for: row.id) })
                    }
                }
                .padding(18)
            }
        }
    }

    private var emptyText: String {
        let trimmedQuery = store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty { return "No apps match \"\(trimmedQuery)\"." }
        switch store.filter {
        case .all: return "No apps available — check back later."
        case .installed: return "Nothing installed yet."
        case .updates: return "Everything is up to date."
        }
    }

    private func errorText(_ e: AppStoreError) -> String {
        switch e {
        case .download: return "Download failed."
        case .checksumMismatch: return "Integrity check failed."
        case .unpack: return "Could not unpack."
        case .invalidBundle: return "Invalid app bundle."
        case .notInstalled(let id): return "\(id) is not available."
        case .notNewer: return "Already up to date."
        }
    }
}
