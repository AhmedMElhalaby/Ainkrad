import SwiftUI

/// The status-driven action controls — Install / Update / Enable / Disable /
/// Uninstall, plus the busy affordance — shared by `AppStoreCard` and
/// `AppStoreDetailView` (AIN-149) so the grid and the detail page never
/// diverge again. `style` scales type size/padding for the card's compact
/// row vs. the detail page's larger header; the callbacks, statuses, and
/// HUD styling are identical in both places.
///
/// Status transitions (available → installed, installed → updateAvailable,
/// …) animate via `.animation(value: row.status)` + per-child
/// `.transition`; the busy/installing state morphs the primary button's
/// label into a spinner in place rather than showing a detached
/// `ProgressView`. All motion is skipped when `accessibilityReduceMotion`
/// is set — state still updates, just without animation.
struct AppStoreActionControls: View {
    enum Style: Equatable {
        case compact
        case prominent

        var fontSize: CGFloat { self == .prominent ? 12 : 11 }
        var buttonHPad: CGFloat { self == .prominent ? 12 : 10 }
        var buttonVPad: CGFloat { self == .prominent ? 5 : 4 }
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: style.spacing) {
            switch row.status {
            case .available:
                actionButton("Install", filled: true, morphsBusy: true, action: onInstall)
                    .transition(rowTransition)
            case .updateAvailable:
                actionButton("Update", filled: true, morphsBusy: true, action: onUpdate)
                    .transition(rowTransition)
                enableToggle
                    .transition(rowTransition)
                if row.isManaged {
                    actionButton("Uninstall", filled: false, morphsBusy: false, action: onUninstall)
                        .transition(rowTransition)
                }
            case .installed:
                installedLabel
                    .transition(rowTransition)
                enableToggle
                    .transition(rowTransition)
                if row.isManaged {
                    actionButton("Uninstall", filled: false, morphsBusy: false, action: onUninstall)
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

    private var enableToggle: some View {
        EnableToggleControl(
            isEnabled: row.isEnabled, tokens: tokens, style: style,
            reduceMotion: reduceMotion, onToggle: onToggleEnabled)
    }

    private func actionButton(_ title: String, filled: Bool, morphsBusy: Bool, action: @escaping () -> Void) -> some View {
        AppStoreActionButton(
            title: title, filled: filled, tokens: tokens, style: style,
            showsSpinner: morphsBusy && isBusy, isDisabled: isBusy,
            reduceMotion: reduceMotion, action: action)
    }
}

/// One pill button — filled (primary) or outline — with hover lift, press
/// scale, and a busy state that crossfades its label for a `ProgressView`
/// in place, instead of a detached spinner floating next to the row.
private struct AppStoreActionButton: View {
    let title: String
    let filled: Bool
    let tokens: DesignTokens
    let style: AppStoreActionControls.Style
    let showsSpinner: Bool
    let isDisabled: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(showsSpinner ? 0 : 1)
                ProgressView().controlSize(.small).opacity(showsSpinner ? 1 : 0)
            }
            .font(.system(size: style.fontSize, weight: .medium))
            .padding(.horizontal, style.buttonHPad).padding(.vertical, style.buttonVPad)
            .background(filled ? tokens.accentPrimary.opacity(0.9) : .clear)
            .foregroundStyle(filled ? tokens.background : tokens.foreground.opacity(0.8))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(tokens.foreground.opacity(filled ? 0 : (isHovering ? 0.35 : 0.2)), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(isHovering && !reduceMotion ? 1.03 : 1.0)
        }
        .buttonStyle(AppStorePressableButtonStyle(reduceMotion: reduceMotion))
        .disabled(isDisabled)
        .onHover { hovering in
            guard !reduceMotion else { isHovering = hovering; return }
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsSpinner)
    }
}

/// A clearer Enable/Disable control than a bare switch: a labeled pill with
/// a status dot, matching the filter chips' HUD language elsewhere in the
/// overlay. Animates its color/label on toggle and lifts slightly on
/// hover/press.
private struct EnableToggleControl: View {
    let isEnabled: Bool
    let tokens: DesignTokens
    let style: AppStoreActionControls.Style
    let reduceMotion: Bool
    let onToggle: (Bool) -> Void

    @State private var isHovering = false

    private var tint: Color { isEnabled ? tokens.accentTertiary : tokens.foreground }

    var body: some View {
        Button { onToggle(!isEnabled) } label: {
            HStack(spacing: 5) {
                Circle().fill(tint.opacity(isEnabled ? 1 : 0.5)).frame(width: 5, height: 5)
                Text(isEnabled ? "Enabled" : "Disabled")
                    .font(.system(size: style.fontSize, weight: .medium))
            }
            .padding(.horizontal, style.buttonHPad - 2).padding(.vertical, style.buttonVPad)
            .foregroundStyle(isEnabled ? tokens.accentTertiary : tokens.foreground.opacity(0.55))
            .background(Capsule().fill(tint.opacity(isHovering ? 0.18 : 0.1)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1))
            .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1.0)
        }
        .buttonStyle(AppStorePressableButtonStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            guard !reduceMotion else { isHovering = hovering; return }
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isEnabled)
        .help(isEnabled ? "Disable" : "Enable")
    }
}

/// Shared press feedback (scale + opacity dip) for action controls across
/// the App Store overlay — also reused by the retained-data Restore/Reset
/// modal buttons in `AppStoreOverlayView`. Skipped entirely under Reduce
/// Motion.
struct AppStorePressableButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
