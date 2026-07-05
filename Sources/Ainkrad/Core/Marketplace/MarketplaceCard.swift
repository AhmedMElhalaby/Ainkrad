import SwiftUI

/// One catalog/app card: icon, name, version line, description, and a trailing
/// action area driven by `row.status` + whether it is busy.
struct MarketplaceCard: View {
    let row: MarketplaceRow
    let tokens: DesignTokens
    let isBusy: Bool
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onToggleEnabled: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(tokens.surfaceElevated)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: row.icon).foregroundStyle(tokens.accentSecondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.displayName)
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground)
                    Text(versionLine)
                        .font(.system(size: 10))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
                Spacer()
                if row.status == .updateAvailable { badge("UPDATE") }
                else if isDevPlugin { badge("DEV") }
            }

            Text(row.description.isEmpty ? " " : row.description)
                .font(.system(size: 11))
                .foregroundStyle(tokens.foreground.opacity(0.7))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surface.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.foreground.opacity(0.1), lineWidth: 1))
    }

    /// A registered plugin that the marketplace didn't install (loaded from
    /// DevPlugins) — present and toggleable, but not uninstallable here.
    private var isDevPlugin: Bool {
        row.kind == .plugin && row.status != .available && !row.isManaged
    }

    private var versionLine: String {
        switch row.status {
        case .available: return "v\(row.catalogVersion ?? "—")"
        case .installed: return row.installedVersion.map { "v\($0) · installed" } ?? "installed"
        case .updateAvailable: return "v\(row.installedVersion ?? "—") → v\(row.catalogVersion ?? "—")"
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            switch row.status {
            case .available:
                actionButton("Install", filled: true, action: onInstall)
            case .updateAvailable:
                actionButton("Update", filled: true, action: onUpdate)
                enableToggle
                if row.isManaged { actionButton("Uninstall", filled: false, action: onUninstall) }
            case .installed:
                Text("Installed").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.accentTertiary)
                enableToggle
                if row.isManaged { actionButton("Uninstall", filled: false, action: onUninstall) }
            }
            Spacer()
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
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(filled ? tokens.accentPrimary.opacity(0.9) : .clear)
                .foregroundStyle(filled ? tokens.background : tokens.foreground.opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tokens.foreground.opacity(filled ? 0 : 0.2), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold)).kerning(0.5)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(tokens.accentSecondary.opacity(0.25)))
            .foregroundStyle(tokens.accentSecondary)
    }
}
