import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The closing step, and the ONLY place `SetupCoordinator.complete()` is called.
///
/// Completion is deliberately concentrated here: `complete()` writes
/// `SetupDocument` to disk immediately, and a marker written anywhere earlier
/// would suppress the first-run gate on every future launch even though the
/// wizard never finished. Every earlier step therefore only calls `advance()`.
///
/// The Keychain line is not decorative. The Home folder is designed to be
/// copied to another Mac, but `Home.keychainServiceName` resolves API keys into
/// this Mac's Keychain — they are not in the vault and do not travel with it. A
/// user who copies their vault and finds their providers gone files a bug;
/// saying it plainly here is cheaper than that bug.
struct SetupDoneStepView: View {
    @Environment(AppEnvironment.self) private var environment

    let coordinator: SetupCoordinator

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Everything is set up. Here is where your things live.")
                        .font(AinkradFont.display(14))
                        .foregroundStyle(tokens.foreground)
                        .fixedSize(horizontal: false, vertical: true)

                    point(title: "In your Home folder",
                          body: "Workspaces, notes, skills, commands, agent history and "
                              + "your settings all live in the folder you chose. It is "
                              + "yours: back it up or copy it to another Mac and your "
                              + "Ainkrad comes with it.",
                          icon: "folder",
                          tokens: tokens)

                    point(title: "Not in your Home folder: your API keys",
                          body: "API keys are stored in this Mac's Keychain, never in "
                              + "your Home folder, and they will not travel with it. If "
                              + "you copy your Home to another Mac, reconnect your "
                              + "providers there once — everything else is already in "
                              + "place.",
                          icon: "key",
                          tokens: tokens)

                    Text("You can change any of these choices later in Settings.")
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }

            HStack {
                // Back is safe here for a structural reason, not by luck: after
                // the Home step adopts a vault the coordinator is rebuilt with
                // `isProvisionalHome: false`, which drops `.home` from `steps`
                // entirely. `back()` walks `steps`, so it cannot return the user
                // to a screen that would re-ask for a Home already adopted.
                AinkradButton(title: "Back", style: .secondary) { coordinator.back() }
                Spacer(minLength: 0)
                AinkradButton(title: "Start using Ainkrad", style: .primary) { finish() }
                    .accessibilityIdentifier("setup.done.finish")
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Marker first, gate second. `complete()` is synchronous and writes before
    /// it returns, so if anything went wrong the gate would still be up on the
    /// next launch rather than the user being dropped into an app whose setup
    /// state says it never happened.
    private func finish() {
        coordinator.complete()
        environment.isSetupPresented = false
    }

    private func point(title: String, body: String, icon: String,
                       tokens: DesignTokens) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tokens.accentSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                Text(body)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.4)))
    }
}
