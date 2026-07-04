import SwiftUI

/// The Marketplace HUD overlay — browse the catalog and install / update /
/// uninstall / enable apps. Same HUD language as the Launcher / Settings.
struct MarketplaceOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var store: MarketplaceStore
    let onDismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        let tokens = environment.themeManager.tokens
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea().onTapGesture { onDismiss() }
            panel(tokens: tokens).frame(width: 820, height: 560).offset(y: -30)
        }
        .task { store.reloadRows() }
    }

    private func panel(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(tokens: tokens)
            LinearGradient(colors: [.clear, tokens.accentPrimary.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            filterBar(tokens: tokens)
            content(tokens: tokens)
        }
        .background(tokens.background.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).strokeBorder(
                LinearGradient(colors: [tokens.accentSecondary.opacity(0.55), tokens.accentPrimary.opacity(0.25)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: tokens.accentPrimary.opacity(0.35), radius: 42)
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    private func header(tokens: DesignTokens) -> some View {
        HStack {
            Text("MARKETPLACE").font(AinkradFont.display(14, weight: .semibold)).kerning(1)
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

    private func chip(_ title: String, _ value: MarketplaceStore.Filter, tokens: DesignTokens) -> some View {
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
                        MarketplaceCard(
                            row: row, tokens: tokens, isBusy: store.busy.contains(row.id),
                            onInstall: { Task { await store.install(row.id) } },
                            onUpdate: { Task { await store.update(row.id) } },
                            onUninstall: { store.uninstall(row.id) },
                            onToggleEnabled: { store.setEnabled($0, for: row.id) })
                    }
                }
                .padding(18)
            }
        }
    }

    private var emptyText: String {
        switch store.filter {
        case .all: return "No apps available — check back later."
        case .installed: return "Nothing installed yet."
        case .updates: return "Everything is up to date."
        }
    }

    private func errorText(_ e: MarketplaceError) -> String {
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
