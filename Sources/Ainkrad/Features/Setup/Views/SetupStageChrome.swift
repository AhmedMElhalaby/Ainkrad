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

    static func transition(reduceMotion: Bool, isForward: Bool = true) -> Transition {
        reduceMotion ? .none : .layered(isForward: isForward)
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
        guard case .layered = transition(reduceMotion: reduceMotion, isForward: isForward) else {
            return .identity
        }
        let travel: CGFloat = isForward ? 1 : -1
        let distance: CGFloat = [26, 34, 46][min(layer.rawValue, 2)]
        let lift: CGFloat = [0, 6, 10][min(layer.rawValue, 2)]

        let insertion = AnyTransition
            .offset(x: travel * distance, y: lift)
            .combined(with: .opacity)
        let removal = AnyTransition
            .offset(x: -travel * distance * 0.6, y: 0)
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

    /// Direction of travel, so forward and back feel distinct. Seeded true —
    /// the first appearance is always forward.
    @State private var isForward = true
    @State private var lastIndex = 0

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
        .onChange(of: coordinator.step) { _, newValue in
            let index = coordinator.steps.firstIndex(of: newValue) ?? 0
            isForward = index >= lastIndex
            lastIndex = index
        }
        .onAppear {
            lastIndex = coordinator.steps.firstIndex(of: coordinator.step) ?? 0
        }
    }

    /// Its own layer: the heading enters ahead of the controls rather than with
    /// them. One idea per screen, stated large.
    private var heading: some View {
        Text(coordinator.step.title)
            .font(AinkradFont.display(30, weight: .semibold))
            .foregroundStyle(tokens.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(SetupStageMotion.layerTransition(
                .heading, reduceMotion: reduceMotion, isForward: isForward))
            .id(coordinator.step)
    }
}
