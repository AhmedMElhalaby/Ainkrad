import SwiftUI
import AinkradAppKit

/// Terminal's root view for a Block: creates its `TerminalSession` on first
/// appearance and hosts it via `TerminalContainerView`. Reads the injected
/// settings store and `host.theme` in `body` so a scheme/font/theme change
/// re-evaluates and restyles the running terminal live.
struct TerminalBlockRootView: View {
    let settingsStore: TerminalSettingsStore
    let theme: HostTheme
    @State private var session: TerminalSession?
    @State private var isNoticeDismissed = false

    var body: some View {
        let appearance = TerminalAppearanceResolver.resolve(
            settings: settingsStore.settings,
            tokens: theme.tokens
        )

        return Group {
            if let session {
                VStack(spacing: 0) {
                    if !session.startupNotices.isEmpty && !isNoticeDismissed {
                        noticeBanner(session.startupNotices)
                    }
                    TerminalContainerView(session: session, appearance: appearance)
                }
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard session == nil else { return }
            session = TerminalSessionFactory(settings: settingsStore.settings).makeSession()
        }
    }

    private func noticeBanner(_ notices: [String]) -> some View {
        let tokens = theme.tokens
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(tokens.accentSecondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(notices, id: \.self) { notice in
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                }
            }
            Spacer()
            Button { isNoticeDismissed = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tokens.surfaceElevated)
    }
}
