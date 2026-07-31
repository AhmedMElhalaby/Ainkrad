import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The opening step, and the first screen anyone ever sees in Ainkrad.
///
/// Deliberately short: one sentence of what this is, one promise about where
/// things are kept, and Continue. Its whole job is to make the folder question
/// on the very next screen make sense — a user who is asked to pick a "Home"
/// with no preamble is being asked to make a decision they have no basis for.
///
/// It writes nothing and asks nothing. No Back button appears because there is
/// nowhere behind it — `SetupStepFooter` omits (rather than disables) Back on
/// the first step — and no skip, because the gate is total.
struct SetupWelcomeStepView: View {
    @Environment(AppEnvironment.self) private var environment

    let coordinator: SetupCoordinator

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Ainkrad is a workspace where AI agents work alongside you — "
                         + "with your terminals, your files and your tools on one surface.")
                        .font(AinkradFont.display(15))
                        .foregroundStyle(tokens.foreground)
                        .fixedSize(horizontal: false, vertical: true)

                    point(title: "Everything lives in one folder you own",
                          body: "Workspaces, notes, skills and agent history are kept as "
                              + "ordinary files in a single folder on your Mac. Nothing is "
                              + "locked in a database, and nothing is stored anywhere you "
                              + "cannot open yourself.",
                          icon: "folder",
                          tokens: tokens)

                    point(title: "A few questions, then you are in",
                          body: "Where that folder goes, how Ainkrad looks and moves, and "
                              + "which AI provider it talks to. Every one of these can be "
                              + "changed later in Settings.",
                          icon: "sparkles",
                          tokens: tokens)
                }
                .padding(20)
            }

            // No Back appears here: `SetupStepFooter` omits it on the first
            // step shown, which for a fresh install is this one.
            SetupStepFooter(coordinator: coordinator,
                            primaryTitle: "Get Started",
                            primaryIdentifier: "setup.welcome.continue") {
                coordinator.advance()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Matches `SetupDoneStepView.point` so the wizard opens and closes in the
    /// same visual language.
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
