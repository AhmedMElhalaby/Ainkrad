import SwiftUI
import AinkradAppKit

/// The status-driven action controls — Install / Update / Enable / Disable /
/// Uninstall, plus the busy affordance — shared by `AppStoreCard` and
/// `AppStoreDetailView` (AIN-149) so the grid and the detail page never
/// diverge again. `style` scales type size/padding for the card's compact
/// row vs. the detail page's larger header; the callbacks, statuses, and
/// HUD styling are identical in both places.
///
/// Status transitions (available → installed, installed → updateAvailable,
/// …) animate via `.animation(value: row.status)` + per-child
/// `.transition`; the busy/installing state crossfades the primary button
/// with an `AinkradSpinner` in place (both views stay mounted; only opacity
/// changes — no structural swap) rather than showing a detached
/// `ProgressView`. All motion is skipped when `ainkradReduceMotion` is set —
/// state still updates, just without animation.
struct AppStoreActionControls: View {
    enum Style: Equatable {
        case compact
        case prominent

        var fontSize: CGFloat { self == .prominent ? 12 : 11 }
        var spinnerSize: CGFloat { self == .prominent ? 18 : 14 }
        var spacing: CGFloat { self == .prominent ? 10 : 8 }
    }

    let row: AppStoreRow
    let tokens: DesignTokens
    let isBusy: Bool
    var style: Style = .compact
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onToggleEnabled: (Bool) -> Void

    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: style.spacing) {
            switch row.status {
            case .available:
                actionButton("Install", style: .primary, morphsBusy: true, action: onInstall)
                    .transition(rowTransition)
            case .updateAvailable:
                actionButton("Update", style: .primary, morphsBusy: true, action: onUpdate)
                    .transition(rowTransition)
                enableToggle
                    .transition(rowTransition)
                if row.isManaged {
                    actionButton("Uninstall", style: .danger, morphsBusy: false, action: onUninstall)
                        .transition(rowTransition)
                }
            case .installed:
                installedLabel
                    .transition(rowTransition)
                enableToggle
                    .transition(rowTransition)
                if row.isManaged {
                    actionButton("Uninstall", style: .danger, morphsBusy: false, action: onUninstall)
                        .transition(rowTransition)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: row.status)
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .identity : .scale(scale: 0.9).combined(with: .opacity)
    }

    private var installedLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: style.fontSize - 1))
            Text("Installed").font(.system(size: style.fontSize, weight: .medium))
        }
        .foregroundStyle(tokens.accentTertiary)
    }

    /// A labeled `AinkradToggle` — the kit's chamfered switch, plus the
    /// Enabled/Disabled caption the bespoke pill used to carry.
    private var enableToggle: some View {
        HStack(spacing: 6) {
            AinkradToggle(isOn: Binding(get: { row.isEnabled }, set: onToggleEnabled))
            Text(row.isEnabled ? "Enabled" : "Disabled")
                .font(.system(size: style.fontSize, weight: .medium))
                .foregroundStyle(row.isEnabled ? tokens.accentTertiary : tokens.foreground.opacity(0.55))
        }
        .help(row.isEnabled ? "Disable" : "Enable")
    }

    /// An `AinkradButton` that, while `morphsBusy && isBusy`, crossfades to
    /// an `AinkradSpinner` in place. Both views are always mounted — only
    /// `.opacity` toggles — so this never swaps the button's identity.
    private func actionButton(_ title: String, style buttonStyle: AinkradButtonStyle, morphsBusy: Bool, action: @escaping () -> Void) -> some View {
        let showsSpinner = morphsBusy && isBusy
        return ZStack {
            AinkradButton(title: title, style: buttonStyle, action: action)
                .opacity(showsSpinner ? 0 : 1)
            AinkradSpinner(size: style.spinnerSize)
                .opacity(showsSpinner ? 1 : 0)
        }
        .disabled(isBusy)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsSpinner)
    }
}
