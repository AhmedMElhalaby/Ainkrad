import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

// MARK: - Rail model

/// The progress rail's data, derived from the coordinator and nothing else.
///
/// Deliberately view-free and pure so it can be tested without SwiftUI, and
/// deliberately WITHOUT a "step n of m" counter. The counter is what jumped
/// confusingly ("3 of 8" → "2 of 7") when the step list shrinks at the vault
/// swap; a rail that shows only the steps actually owed removes the
/// contradiction rather than papering over it.
struct SetupRailModel {
    struct Item: Identifiable, Equatable {
        let step: SetupStep
        let title: String
        /// Exactly one item is current — the coordinator has exactly one `step`.
        let isCurrent: Bool
        /// True for steps already walked past. Never true for the current one:
        /// the user is still standing on it.
        let isComplete: Bool

        var id: String { step.rawValue }
    }

    let items: [Item]

    /// `@MainActor` only because `SetupCoordinator` is — the resulting value is
    /// plain data and travels anywhere.
    @MainActor
    init(coordinator: SetupCoordinator) {
        let steps = coordinator.steps
        let currentIndex = steps.firstIndex(of: coordinator.step) ?? 0
        items = steps.enumerated().map { index, step in
            Item(step: step,
                 title: step.title,
                 isCurrent: index == currentIndex,
                 isComplete: index < currentIndex)
        }
    }
}

// MARK: - Motion policy

/// The stage's motion policy, kept separate from the views so the one rule that
/// actually matters — reduce-motion collapses everything — is unit-testable.
///
/// The wizard SETS `uiReduceMotion` two steps in. A user who turns it on at
/// Motion & Sound must see the remaining steps stop moving immediately; that is
/// the most visible possible proof the setting works, and animating anyway is
/// worse than never having animated at all.
enum SetupStageMotion {
    /// What the stage does when the step changes. `.none` is the whole point of
    /// this type existing: it is the seam reduce-motion collapses to.
    enum Transition: Equatable {
        case none
        /// Layers enter offset in the direction of travel and stagger in.
        case layered(isForward: Bool)
    }

    /// The layers, outermost first. Each one animates as its own element — the
    /// design language's "separated live layers, not one whole image moving".
    enum Layer: Int, CaseIterable {
        case rail = 0, heading, content
    }

    /// How far and how late a layer moves. Pure data so the geometry — and the
    /// reduce-motion guard in front of it — can be asserted without SwiftUI.
    struct LayerGeometry: Equatable {
        /// Signed horizontal travel of the ENTERING layer, in points. Negative
        /// when going back, which is what makes the two directions distinct.
        let travel: CGFloat
        let lift: CGFloat
        let delay: Double
    }

    /// Direction of travel between two steps. A free function of the two step
    /// indices, so it can be computed during body evaluation from the step being
    /// rendered rather than recovered afterwards.
    static func isForward(from previousIndex: Int, to nextIndex: Int) -> Bool {
        nextIndex >= previousIndex
    }

    static func transition(reduceMotion: Bool, isForward: Bool = true) -> Transition {
        reduceMotion ? .none : .layered(isForward: isForward)
    }

    /// `nil` under reduce-motion — the seam that makes `layerTransition` fall
    /// back to `.identity`.
    static func layerGeometry(_ layer: Layer,
                              reduceMotion: Bool,
                              isForward: Bool) -> LayerGeometry? {
        guard case .layered = transition(reduceMotion: reduceMotion, isForward: isForward) else {
            return nil
        }
        // A `switch`, not an indexed array: a fourth Layer case must fail to
        // compile rather than silently inherit the third one's geometry.
        let distance: CGFloat
        let lift: CGFloat
        switch layer {
        case .rail:    distance = 26; lift = 0
        case .heading: distance = 34; lift = 6
        case .content: distance = 46; lift = 10
        }
        return LayerGeometry(travel: isForward ? distance : -distance,
                             lift: lift,
                             delay: Double(layer.rawValue) * 0.055)
    }

    /// `nil` under reduce-motion, which makes every `withAnimation` /
    /// `.animation` call site a no-op without a branch at each one.
    static func animation(reduceMotion: Bool, layer: Layer = .rail) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.42, dampingFraction: 0.82)
            .delay(Double(layer.rawValue) * 0.055)
    }

    /// The per-layer entry/exit. Forward and back are directionally distinct
    /// (content arrives from the side it is travelling from), and each layer
    /// carries a slightly different distance and delay so they do not read as
    /// one plane sliding.
    static func layerTransition(_ layer: Layer,
                                reduceMotion: Bool,
                                isForward: Bool) -> AnyTransition {
        guard let geometry = layerGeometry(layer,
                                           reduceMotion: reduceMotion,
                                           isForward: isForward) else {
            return .identity
        }

        let insertion = AnyTransition
            .offset(x: geometry.travel, y: geometry.lift)
            .combined(with: .opacity)
        let removal = AnyTransition
            .offset(x: -geometry.travel * 0.6, y: 0)
            .combined(with: .opacity)

        return AnyTransition
            .asymmetric(insertion: insertion, removal: removal)
            .animation(animation(reduceMotion: reduceMotion, layer: layer))
    }
}

// MARK: - Rail

/// The thin progress rail across the top of the stage.
///
/// Spatial, not numeric: one segment per owed step, the current one lit and
/// slightly taller, the walked-past ones filled, the rest recessed. No text —
/// VoiceOver gets the words instead, where they cost the visual design nothing.
struct SetupRail: View {
    let model: SetupRailModel
    let tokens: DesignTokens
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.items) { item in
                Capsule()
                    .fill(fill(for: item))
                    .frame(height: item.isCurrent ? 4 : 2)
                    .frame(maxWidth: .infinity)
                    // Explicit: SwiftUI does not reliably expose a decorative
                    // shape as an accessibility element, so without this the
                    // labels below never reach VoiceOver despite the
                    // `children: .contain` group.
                    .accessibilityElement()
                    .accessibilityLabel(item.isCurrent
                                        ? "Current step: \(item.title)"
                                        : item.title)
            }
        }
        .frame(height: 4)
        .animation(SetupStageMotion.animation(reduceMotion: reduceMotion),
                   value: model.items)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
    }

    private func fill(for item: SetupRailModel.Item) -> Color {
        if item.isCurrent { return tokens.accentPrimary }
        if item.isComplete { return tokens.accentSecondary.opacity(0.7) }
        return tokens.foreground.opacity(0.16)
    }
}

// MARK: - Stage

/// The full-bleed wizard container: rail at the top, the step's own heading and
/// content in the middle with room around them, and the step's nav row at the
/// bottom.
///
/// There is no panel. `.hudPanelChrome` is gone deliberately — the wizard now
/// lays out against the window, over the scrim, with the living island reading
/// through it. The scrim itself stays (`SetupOverlayView`), and it stays without
/// a tap gesture: this overlay is non-dismissible.
///
/// The nav row is not built here. Every step view already ends in the shared
/// `SetupStepFooter`, which owns that step's primary title, its disabled state
/// and its action; the stage gives the step the full height so that footer
/// lands at the bottom of the stage. Absorbing it rather than duplicating it is
/// what keeps ONE Back in the wizard.
struct SetupStage<Content: View>: View {
    let coordinator: SetupCoordinator
    let tokens: DesignTokens
    let reduceMotion: Bool
    @ViewBuilder let content: (SetupStep) -> Content

    /// The index the stage was LAST rendering. Updated in `onChange`, i.e. after
    /// the render that observed the step change — which is exactly why direction
    /// is computed from it in `body` rather than assigned there.
    ///
    /// An earlier version assigned `isForward` inside `onChange` and read it
    /// from `body`. `onChange` runs after the update that observed the change,
    /// so every transition was computed from the PREVIOUS direction and the
    /// first Back animated as a forward. Deriving it during body evaluation
    /// means the transition and the direction it depends on come from the same
    /// change.
    @State private var lastIndex = 0

    private var currentIndex: Int {
        coordinator.steps.firstIndex(of: coordinator.step) ?? 0
    }

    /// Seeded forward: the first appearance has nowhere to have come back from.
    private var isForward: Bool {
        SetupStageMotion.isForward(from: lastIndex, to: currentIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            SetupRail(model: SetupRailModel(coordinator: coordinator),
                      tokens: tokens,
                      reduceMotion: reduceMotion)
                .padding(.horizontal, 34)
                .padding(.top, 22)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 22) {
                heading
                content(coordinator.step)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(SetupStageMotion.layerTransition(
                        .content, reduceMotion: reduceMotion, isForward: isForward))
                    .id(coordinator.step)
            }
            .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            // Makes the step change an animated transaction at all; each
            // layer's own `.animation` (with its stagger delay) then wins for
            // that layer. `nil` under reduce-motion, so the whole thing snaps.
            .animation(SetupStageMotion.animation(reduceMotion: reduceMotion),
                       value: coordinator.step)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Only ever CATCHES UP; it never decides the direction. `body` has
        // already rendered this change using the old value, which is the point.
        .onChange(of: coordinator.step) { _, newValue in
            lastIndex = coordinator.steps.firstIndex(of: newValue) ?? 0
        }
        .onAppear {
            lastIndex = currentIndex
        }
    }

    /// Its own layer: the heading enters ahead of the controls rather than with
    /// them. One idea per screen, stated large.
    private var heading: some View {
        // `headline`, not `title`: the rail still labels this step "Welcome",
        // but the stage says what Ainkrad actually is. See `SetupStep.headline`.
        Text(coordinator.step.headline)
            .font(AinkradFont.display(30, weight: .semibold))
            .foregroundStyle(tokens.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(SetupStageMotion.layerTransition(
                .heading, reduceMotion: reduceMotion, isForward: isForward))
            .id(coordinator.step)
    }
}
