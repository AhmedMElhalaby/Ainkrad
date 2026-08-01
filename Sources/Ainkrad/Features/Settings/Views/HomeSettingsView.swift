import SwiftUI
import AppKit
import AinkradAppKit
import AinkradHostRuntime

/// Where the user's Ainkrad Home lives. Read-only: see the file header
/// rationale in the plan/spec — moving the vault rebuilds the environment and
/// is a pre-bootstrap operation, not a settings toggle. `SetupCoordinator`
/// encodes the same rule (`.home` is never re-asked on a completed vault).
///
/// `AppEnvironment` does not carry a `home` property of its own — every
/// on-disk path is derived from the `Home` it was bootstrapped with, but that
/// value isn't retained on the instance. `AinkradHome.resolve()` (the same
/// call `SetupHomeStepView` reads its adopted path from) is the real, current
/// source of truth for the vault root, so this pane reads it directly rather
/// than inventing a new accessor on `AppEnvironment`.
struct HomeSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// The adopted vault's root, or `nil` while the Home is still provisional
    /// (setup incomplete). Settings is unreachable before setup finishes, so
    /// in practice this is always non-`nil` here — the guard exists so this
    /// pane never mislabels a throwaway temp directory as the user's real
    /// Home if it is ever reached in that state.
    ///
    /// Resolved once in `.onAppear` rather than as a computed property:
    /// `AinkradHome.resolve()` hits disk (`HomePointer.read` +
    /// `FileManager.fileExists`), and this view observes `AppEnvironment`
    /// (`@Observable`), so any unrelated environment mutation re-runs `body`.
    /// Relocating the Home is a pre-bootstrap-only operation — the wizard
    /// does it, this pane deliberately has no move control — so the vault
    /// root cannot change while Settings is open, making a one-time resolve
    /// safe.
    @State private var vaultRoot: URL?

    var body: some View {
        AinkradSettingsPanel(
            title: "Ainkrad Home",
            hint: "Every workspace, note and project you create lives in this folder. "
                + "Moving it is done during setup, not here."
        ) {
            VStack(alignment: .leading, spacing: 9) {
                Text(displayPath)
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(environment.themeManager.tokens.foreground.opacity(0.8))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                AinkradButton(title: "Reveal in Finder", style: .secondary) {
                    reveal(vaultRoot)
                }
                .disabled(vaultRoot == nil)
            }
            .onAppear {
                guard !environment.isProvisionalHome else { return }
                guard case .ready(let home) = AinkradHome.resolve() else { return }
                vaultRoot = home.vaultRoot
            }
        }
    }

    /// Tilde form, as the setup step shows it — an absolute path under
    /// /Users/<name> is noise the user already knows.
    private var displayPath: String {
        guard let vaultRoot else { return "Not set up yet" }
        let path = vaultRoot.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
