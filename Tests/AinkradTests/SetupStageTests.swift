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

    // Forward and back must be directionally distinct, so the policy has to
    // carry a direction and collapse it only under reduce-motion.
    @Test func directionSurvivesUntilReduceMotionCollapsesIt() {
        #expect(SetupStageMotion.transition(reduceMotion: false, isForward: true)
                != SetupStageMotion.transition(reduceMotion: false, isForward: false))
        #expect(SetupStageMotion.transition(reduceMotion: true, isForward: true)
                == SetupStageMotion.transition(reduceMotion: true, isForward: false))
    }
}
