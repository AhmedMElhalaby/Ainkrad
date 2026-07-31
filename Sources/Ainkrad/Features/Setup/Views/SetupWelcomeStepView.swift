import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The opening step, and the first screen anyone ever sees in Ainkrad.
///
/// The quietest screen in the wizard, on purpose. A headline saying what
/// Ainkrad is (`SetupStep.headline`, rendered at 30pt by the stage) and ONE
/// paragraph saying where the work lives. Nothing to fill in.
///
/// It is one idea, counted honestly. The first pass at this screen replaced two
/// chamfered feature cards with three paragraphs — which is the same three
/// ideas the cards carried, merely set as prose, and just as much a stack. What
/// survives is the folder promise, because that is the one thing the very next
/// screen needs the user to already believe: someone asked to pick a "Home"
/// with no preamble is being asked to decide something they have no basis for.
///
/// What was cut, and why:
/// - The "one surface" paragraph, whose "the work and the help with the work
///   are never in two different places" read as written rather than said. The
///   headline already makes that point in nine words.
/// - The "here is what the next few screens ask" paragraph. That is the
///   progress rail's job, and the rail is on screen while it was being read.
///
/// It writes nothing and asks nothing. No Back button appears because there is
/// nowhere behind it — `SetupStepFooter` omits (rather than disables) Back on
/// the first step — and no skip, because the gate is total.
struct SetupWelcomeStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    let coordinator: SetupCoordinator

    /// Drives the one piece of motion on this screen: the paragraph settles in
    /// a beat after the headline lands, rather than arriving with it — a
    /// separated layer, not one block fading. Flat off under reduce-motion,
    /// where the delay and the offset below both collapse to zero because
    /// `SetupStageMotion.layerGeometry` returns `nil`.
    @State private var hasSettled = false

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                paragraph(
                    // "it" referred back to a paragraph that is now cut; with
                    // only the headline above, the subject has to be named.
                    "Everything you and your agents make — your workspaces, your "
                        + "notes, your skills, every conversation you have — is kept "
                        + "as ordinary files in a single folder on your Mac. Not a "
                        + "database, not an account somewhere. A folder you can open, "
                        + "back up, or carry to another machine.",
                    tokens: tokens)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 620, alignment: .leading)
            }
            .onAppear { settle() }

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

    /// Routed through `SetupStageMotion` rather than a bare `.animation(...)`,
    /// so the wizard has exactly one place where reduce-motion is honoured.
    /// `.content` is the stage layer this text belongs to.
    private func settle() {
        guard !hasSettled else { return }
        withAnimation(SetupStageMotion.animation(reduceMotion: reduceMotion,
                                                 layer: .content)) {
            hasSettled = true
        }
    }

    private func paragraph(_ text: String, tokens: DesignTokens) -> some View {
        let size: CGFloat = 17
        let geometry = SetupStageMotion.layerGeometry(.content,
                                                      reduceMotion: reduceMotion,
                                                      isForward: true)
        // `nil` geometry is reduce-motion: no lift, no stagger, nothing to fade
        // from. The text is simply there.
        let lift = geometry.map(\.lift) ?? 0
        let delay = geometry.map(\.delay) ?? 0

        return Text(text)
            .font(AinkradFont.display(size))
            .foregroundStyle(tokens.foreground.opacity(0.92))
            .lineSpacing(size * 0.34)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(hasSettled ? 1 : 0)
            .offset(y: hasSettled ? 0 : lift)
            .animation(SetupStageMotion.animation(reduceMotion: reduceMotion,
                                                  layer: .content)?.delay(delay),
                       value: hasSettled)
    }
}
