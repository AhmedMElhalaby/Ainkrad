import SwiftUI
import AinkradAppKit

/// One catalog/app card: icon, name, version line, description, and a trailing
/// action area driven by `row.status` + whether it is busy. Tapping the
/// icon/name/description area opens the app's detail page (AIN-147); the
/// actions row below is excluded so Install/Update/Uninstall/enable taps
/// don't also trigger navigation. The actions themselves live in the shared
/// `AppStoreActionControls` (AIN-149) so the grid card and the detail page
/// never diverge. The chamfer, hover glow, and border-brighten (skipped
/// under Reduce Motion) all come from `AinkradCard` — this view only wires
/// the open-vs-actions hit split on top of it: `AinkradCard`'s own `onTap`
/// is left `nil` so the whole card never routes taps, and `onOpen` is
/// attached only to the content sub-area above the actions row.
struct AppStoreCard: View {
    let row: AppStoreRow
    let tokens: DesignTokens
    let isBusy: Bool
    let onOpen: () -> Void
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onToggleEnabled: (Bool) -> Void

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        NeonAppTile(symbol: row.icon, tokens: tokens, size: 30)
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
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                AppStoreActionControls(
                    row: row, tokens: tokens, isBusy: isBusy,
                    onInstall: onInstall, onUpdate: onUpdate, onUninstall: onUninstall, onToggleEnabled: onToggleEnabled)
            }
        }
    }

    /// A registered plugin that the App Store didn't install (loaded from
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

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold)).kerning(0.5)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(tokens.accentSecondary.opacity(0.25)))
            .foregroundStyle(tokens.accentSecondary)
    }
}
