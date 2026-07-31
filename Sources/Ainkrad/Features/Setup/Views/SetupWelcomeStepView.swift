import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The opening step, and the first screen anyone ever sees in Ainkrad.
///
/// The quietest screen in the wizard, on purpose. It states one idea — your
/// work lives in a folder you own — in prose, at a size you read rather than
/// scan, and asks for nothing. Its job is to make the folder question on the
/// very next screen make sense: a user asked to pick a "Home" with no preamble
/// is being asked to decide something they have no basis for.
///
/// The two chamfered feature cards that used to sit here are gone. Three
/// bullet-shaped tiles is the shape the rest of this redesign is moving away
/// from, and on the one screen with nothing to fill in there is no reason to
/// imitate a form. The headline itself carries the "what is this" — see
/// `SetupStep.headline`, which the stage renders at 30pt.
///
/// It writes nothing and asks nothing. No Back button appears because there is
/// nowhere behind it — `SetupStepFooter` omits (rather than disables) Back on
/// the first step — and no skip, because the gate is total.
struct SetupWelcomeStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    let coordinator: SetupCoordinator

    /// Drives the one piece of motion on this screen: the two paragraphs and
    /// the closing line settle in after the headline, each a beat behind the
    /// last. Separated layers, not one block fading — and flat off under
    /// reduce-motion, where every delay and offset below collapses to zero
    /// because `SetupStageMotion.layerGeometry` returns `nil`.
    @State private var hasSettled = false

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    paragraph(
                        "Your terminals, your files, your tools and your agents share "
                            + "one surface, so the work and the help with the work are "
                            + "never in two different places.",
                        size: 17,
                        opacity: 0.92,
                        layer: 0,
                        tokens: tokens)

                    paragraph(
                        "Everything it makes — your workspaces, your notes, your skills, "
                            + "every conversation you have with it — is kept as ordinary "
                            + "files in a single folder on your Mac. Not a database, not "
                            + "an account somewhere. A folder you can open, back up, or "
                            + "carry to another machine.",
                        size: 17,
                        opacity: 0.92,
                        layer: 1,
                        tokens: tokens)

                    paragraph(
                        "The next few screens ask where that folder should go, how "
                            + "Ainkrad should look and move, and which AI it should talk "
                            + "to. None of it is permanent — you can change any of it "
                            + "later in Settings.",
                        size: 14,
                        opacity: 0.58,
                        layer: 2,
                        tokens: tokens)
                }
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
    /// so the wizard has exactly one place where reduce-motion is honoured. The
    /// `layer` index only stages the delay; `.content` is the stage layer these
    /// all belong to.
    private func settle() {
        guard !hasSettled else { return }
        withAnimation(SetupStageMotion.animation(reduceMotion: reduceMotion,
                                                 layer: .content)) {
            hasSettled = true
        }
    }

    private func paragraph(_ text: String, size: CGFloat, opacity: Double,
                           layer: Int, tokens: DesignTokens) -> some View {
        let geometry = SetupStageMotion.layerGeometry(.content,
                                                      reduceMotion: reduceMotion,
                                                      isForward: true)
        // `nil` geometry is reduce-motion: no lift, no stagger, nothing to fade
        // from. The text is simply there.
        let lift = geometry.map { $0.lift + CGFloat(layer) * 4 } ?? 0
        let delay = geometry.map { $0.delay + Double(layer) * 0.07 } ?? 0

        return Text(text)
            .font(AinkradFont.display(size))
            .foregroundStyle(tokens.foreground.opacity(opacity))
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
