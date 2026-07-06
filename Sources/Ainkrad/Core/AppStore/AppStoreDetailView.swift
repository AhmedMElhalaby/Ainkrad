import SwiftUI

/// The App Store's per-app detail page (AIN-147): large icon, name, author,
/// version, long description, screenshot gallery, links, and the primary
/// action + enable/uninstall — reusing the exact same `AppStoreStore`
/// actions `AppStoreCard` uses in the grid. `AppStoreOverlayView` shows this
/// in place of the grid while `store.selectedAppID != nil`.
struct AppStoreDetailView: View {
    /// The full catalog record, when the app is in the cached catalog. `nil`
    /// for a built-in with no catalog entry — the view falls back to what
    /// `row` carries.
    let entry: CatalogEntry?
    let row: AppStoreRow
    let tokens: DesignTokens
    let isBusy: Bool
    let onBack: () -> Void
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onToggleEnabled: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                backButton
                header
                Text(longDescriptionText)
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foreground.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if let screenshots = entry?.screenshots, !screenshots.isEmpty {
                    screenshotGallery(screenshots)
                }
                if let links = entry?.links, !links.isEmpty {
                    linksRow(links)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tokens.foreground.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help("Back to catalog")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            RoundedRectangle(cornerRadius: 16)
                .fill(tokens.surfaceElevated)
                .frame(width: 76, height: 76)
                .overlay(Image(systemName: row.icon).font(.system(size: 32)).foregroundStyle(tokens.accentSecondary))
            VStack(alignment: .leading, spacing: 5) {
                Text(row.displayName)
                    .font(AinkradFont.display(20, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                if let author = entry?.author, !author.isEmpty {
                    Text("by \(author)")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                }
                Text(versionLine)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                actions.padding(.top, 4)
            }
            Spacer()
        }
    }

    private var longDescriptionText: String {
        let text = entry?.longDescription ?? row.description
        return text.isEmpty ? " " : text
    }

    private var versionLine: String {
        switch row.status {
        case .available: return "v\(row.catalogVersion ?? "—")"
        case .installed: return row.installedVersion.map { "v\($0) · installed" } ?? "installed"
        case .updateAvailable: return "v\(row.installedVersion ?? "—") → v\(row.catalogVersion ?? "—")"
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            switch row.status {
            case .available:
                actionButton("Install", filled: true, action: onInstall)
            case .updateAvailable:
                actionButton("Update", filled: true, action: onUpdate)
                enableToggle
                if row.isManaged { actionButton("Uninstall", filled: false, action: onUninstall) }
            case .installed:
                Text("Installed").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.accentTertiary)
                enableToggle
                if row.isManaged { actionButton("Uninstall", filled: false, action: onUninstall) }
            }
            if isBusy { ProgressView().controlSize(.small) }
        }
    }

    private var enableToggle: some View {
        Toggle("", isOn: Binding(get: { row.isEnabled }, set: { onToggleEnabled($0) }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(row.isEnabled ? "Enabled" : "Disabled")
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(filled ? tokens.accentPrimary.opacity(0.9) : .clear)
                .foregroundStyle(filled ? tokens.background : tokens.foreground.opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tokens.foreground.opacity(filled ? 0 : 0.2), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    // MARK: - Screenshot gallery

    private func screenshotGallery(_ urls: [URL]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(urls, id: \.self) { url in
                    screenshot(url)
                }
            }
        }
    }

    private func screenshot(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                screenshotBox(systemImage: "exclamationmark.triangle", tint: tokens.accentTertiary)
            default:
                screenshotBox(systemImage: nil, tint: tokens.foreground)
            }
        }
        .frame(width: 220, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.foreground.opacity(0.1), lineWidth: 1))
    }

    private func screenshotBox(systemImage: String?, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated)
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(tint.opacity(0.7))
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Links

    private func linksRow(_ links: [ManifestLink]) -> some View {
        HStack(spacing: 16) {
            ForEach(links, id: \.url) { link in
                Link(destination: link.url) {
                    HStack(spacing: 4) {
                        Text(link.title)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.accentSecondary)
                }
            }
        }
    }
}
