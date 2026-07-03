import SwiftUI

/// Terminal's root view for a Block: creates its `TerminalSession` on
/// first appearance and hosts it via `TerminalContainerView`. See
/// Terminal App Architecture.md.
struct TerminalBlockRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var session: TerminalSession?
    @State private var isNoticeDismissed = false

    var body: some View {
        // Reading the settings store and theme here means a color-scheme,
        // font, or theme change re-evaluates this body and hands the container
        // a fresh appearance, restyling the running terminal live.
        let appearance = TerminalAppearanceResolver.resolve(
            settings: environment.terminalSettingsStore.settings,
            theme: environment.themeManager.currentTheme
        )

        return Group {
            if let session {
                VStack(spacing: 0) {
                    if !session.startupNotices.isEmpty && !isNoticeDismissed {
                        noticeBanner(session.startupNotices)
                    }
                    // A translucent terminal reveals the shared workspace
                    // backdrop (one blurred island behind all panes — see
                    // TileLayoutView), so all windows float over one
                    // background rather than each carrying its own.
                    TerminalContainerView(session: session, appearance: appearance)
                }
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard session == nil else { return }
            session = TerminalSessionFactory(settingsStore: environment.settingsStore).makeSession()
        }
    }

    /// Calm, non-blocking inline surfacing of resolution fallbacks — never
    /// a modal, and dismissible. See Terminal App Architecture.md.
    private func noticeBanner(_ notices: [String]) -> some View {
        let tokens = environment.themeManager.tokens

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
            Button {
                isNoticeDismissed = true
            } label: {
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
