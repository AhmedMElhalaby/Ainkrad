import Foundation
import Testing
@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("Setup stage")
@MainActor
struct SetupStageTests {
    // The rail shows the steps actually owed, so there is no denominator that
    // can contradict itself when the step list changes at the vault swap.
    @Test func theRailReflectsOwedStepsNotAFixedCount() {
        let store = InMemoryPersistenceStore()
        let provisional = SetupCoordinator(persistence: store, isProvisionalHome: true)
        let adopted = SetupCoordinator(persistence: store, isProvisionalHome: false)

        #expect(SetupRailModel(coordinator: provisional).items.count == provisional.steps.count)
        #expect(SetupRailModel(coordinator: adopted).items.count == adopted.steps.count)
        #expect(!SetupRailModel(coordinator: adopted).items.contains { $0.step == .home })
    }

    @Test func theRailMarksExactlyOneStepCurrent() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        c.advance()
        let items = SetupRailModel(coordinator: c).items
        #expect(items.filter(\.isCurrent).count == 1)
        #expect(items.first(where: \.isCurrent)?.step == c.step)
    }

    // Reduce-motion is set two steps into this wizard. The remaining steps must
    // honour it immediately — it is the most visible proof the setting works.
    @Test func reduceMotionRemovesTheStageTransition() {
        #expect(SetupStageMotion.transition(reduceMotion: true) == .none)
        #expect(SetupStageMotion.transition(reduceMotion: false) != .none)
    }

    // Steps behind the current one read as done; steps ahead do not. This is
    // what makes the rail spatial — the lit segment IS the position.
    @Test func theRailMarksOnlyPassedStepsComplete() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        c.advance()
        c.advance()
        let items = SetupRailModel(coordinator: c).items
        let current = items.firstIndex(where: { $0.isCurrent }) ?? 0
        let behindAllComplete = items[..<current].allSatisfy { $0.isComplete }
        let aheadNoneComplete = !items[current...].contains { $0.isComplete }
        #expect(behindAllComplete)
        #expect(aheadNoneComplete)
    }

    // `transition` is only ONE of the three reduce-motion seams. This is the
    // second: `animation` returning nil is what makes the container's and the
    // rail's `.animation(_, value:)` no-ops. Without this test its guard could
    // be deleted and the rail would keep animating with the suite still green.
    @Test func reduceMotionRemovesTheStageAnimation() {
        for layer in SetupStageMotion.Layer.allCases {
            #expect(SetupStageMotion.animation(reduceMotion: true, layer: layer) == nil)
            #expect(SetupStageMotion.animation(reduceMotion: false, layer: layer) != nil)
        }
    }

    // The third seam: the per-layer geometry, which is what `layerTransition`
    // falls back to `.identity` on.
    @Test func reduceMotionRemovesEveryLayerGeometry() {
        for layer in SetupStageMotion.Layer.allCases {
            #expect(SetupStageMotion.layerGeometry(layer, reduceMotion: true,
                                                   isForward: true) == nil)
            #expect(SetupStageMotion.layerGeometry(layer, reduceMotion: true,
                                                   isForward: false) == nil)
            #expect(SetupStageMotion.layerGeometry(layer, reduceMotion: false,
                                                   isForward: true) != nil)
        }
    }

    // Each layer must travel a different distance, or they read as one plane
    // sliding rather than separated live layers.
    @Test func layersTravelIndependently() {
        let distances = SetupStageMotion.Layer.allCases.compactMap {
            SetupStageMotion.layerGeometry($0, reduceMotion: false, isForward: true)
        }
        #expect(distances.count == SetupStageMotion.Layer.allCases.count)
        #expect(Set(distances.map(\.travel)).count == distances.count)
        #expect(Set(distances.map(\.delay)).count == distances.count)
    }

    // Direction is a pure function of the two step indices so the stage can
    // compute it DURING body evaluation. Deriving it afterwards (in onChange)
    // left every transition one step behind, and the first Back animated as a
    // forward.
    @Test func directionComesFromTheStepIndicesAlone() {
        #expect(SetupStageMotion.isForward(from: 2, to: 3))
        #expect(!SetupStageMotion.isForward(from: 3, to: 2))
        // No movement is not "backwards": the first render compares a step
        // against itself and must not animate in reverse.
        #expect(SetupStageMotion.isForward(from: 0, to: 0))
    }

    // Forward and back must be directionally distinct, so the policy has to
    // carry a direction and collapse it only under reduce-motion.
    @Test func directionSurvivesUntilReduceMotionCollapsesIt() {
        #expect(SetupStageMotion.transition(reduceMotion: false, isForward: true)
                != SetupStageMotion.transition(reduceMotion: false, isForward: false))
        #expect(SetupStageMotion.transition(reduceMotion: true, isForward: true)
                == SetupStageMotion.transition(reduceMotion: true, isForward: false))
    }
}
