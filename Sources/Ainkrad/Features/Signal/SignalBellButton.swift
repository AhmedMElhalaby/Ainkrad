import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The notification bell in the app's own top bar, beside the workspace
/// diamonds.
///
/// It floats directly on the sky with no background tint and no separator,
/// matching `HUDBar`'s rule for that strip — the chamfered chip treatment
/// belongs to the readouts on the left (clock, network, battery), not here.
///
/// Living in-window rather than on `NSStatusBar` also means the first-run
/// setup gate covers it for free: the scrim is a full-screen surface inside
/// the window, so there is nothing here that can be reached around it.
struct SignalBellButton: View {
    let unread: Int
    /// Quiet hours or a snooze is in force. The bell says so, because silence
    /// the user cannot see is indistinguishable from breakage — and the support
    /// question it produces is "notifications stopped working".
    var isMuted: Bool = false
    let tokens: DesignTokens
    let action: () -> Void

    @State private var isHovered = false

    /// Capped so a busy session cannot widen the bar and shove the workspace
    /// diamonds along.
    static func badgeText(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case ...99: return String(count)
        default: return "99+"
        }
    }

    /// Static and pure so the three-way choice is testable without rendering.
    static func glyphName(unread: Int, isMuted: Bool) -> String {
        if isMuted { return "bell.slash" }
        return unread > 0 ? "bell.fill" : "bell"
    }

    private var hasUnread: Bool { unread > 0 }

    /// Names the reason as well as the count. A muted bell with three unread is
    /// two facts, and the tooltip is the only place either is written down.
    private var helpText: String {
        let count = hasUnread
            ? "\(unread) unread notification\(unread == 1 ? "" : "s")"
            : "Notifications"
        return isMuted ? "\(count) — quiet hours are on" : count
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: Self.glyphName(unread: unread, isMuted: isMuted))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(hasUnread
                                     ? tokens.accentSecondary
                                     : tokens.foreground.opacity(isHovered ? 0.75 : 0.4))
                    // The glyph is its own layer: it lifts on hover rather than
                    // the whole control moving.
                    .scaleEffect(isHovered ? 1.14 : 1)
                    .shadow(color: hasUnread ? tokens.accentSecondary.opacity(0.8) : .clear,
                            radius: 4)

                if let badge = Self.badgeText(unread) {
                    Text(badge)
                        .font(AinkradFont.mono(9.5, weight: .semibold))
                        .foregroundStyle(tokens.accentSecondary)
                }
            }
            .frame(minWidth: 14, minHeight: 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { isHovered = hovering }
        }
    }
}
