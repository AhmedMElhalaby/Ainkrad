import SwiftUI

/// Terminal's root view for a Block: creates its `TerminalSession` on
/// first appearance and hosts it via `TerminalContainerView`. See
/// Terminal App Architecture.md.
struct TerminalBlockRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var session: TerminalSession?
    @State private var isNoticeDismissed = false

    var body: some View {
        Group {
            if let session {
                VStack(spacing: 0) {
                    if !session.startupNotices.isEmpty && !isNoticeDismissed {
                        noticeBanner(session.startupNotices)
                    }
                    TerminalContainerView(session: session)
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
