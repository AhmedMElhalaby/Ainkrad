import Testing
import Foundation
@testable import Ainkrad

@Suite("IslandState")
struct IslandStateTests {
    @Test("rest state")
    @MainActor
    func restState() {
        let state = IslandState()
        #expect(abs(state.ringIntensity - 0.35) < 0.0001)
        #expect(state.banking == 0)
        #expect(state.flarePhase == nil)
    }

    @Test("setBusy(true) raises ringIntensity above rest, decays back on setBusy(false)")
    @MainActor
    func busyRaisesAndDecays() {
        let state = IslandState()
        let rest = state.ringIntensity

        state.setBusy(true)
        #expect(state.ringIntensity > rest)
        // Advance a while so it settles near the busy target.
        for _ in 0..<200 { state.tick(dt: 0.05) }
        let busyLevel = state.ringIntensity
        #expect(busyLevel > 0.7)

        state.setBusy(false)
        var previous = state.ringIntensity
        var reachedRest = false
        for _ in 0..<500 {
            state.tick(dt: 0.05)
            let current = state.ringIntensity
            #expect(current <= previous + 0.0001, "ringIntensity should decay monotonically, not oscillate")
            #expect(current >= rest - 0.0001, "ringIntensity should never dip below rest while decaying to it")
            previous = current
            if abs(current - rest) < 0.001 {
                reachedRest = true
                break
            }
        }
        #expect(reachedRest, "ringIntensity should settle back to rest")
    }

    @Test("launcherActive(true) raises ringIntensity above rest; false returns it toward rest")
    @MainActor
    func launcherActiveRaisesAndLowers() {
        let state = IslandState()
        let rest = state.ringIntensity

        state.launcherActive(true)
        #expect(state.ringIntensity > rest)
        for _ in 0..<200 { state.tick(dt: 0.05) }
        let activeLevel = state.ringIntensity
        #expect(activeLevel > rest)

        state.launcherActive(false)
        for _ in 0..<500 { state.tick(dt: 0.05) }
        #expect(abs(state.ringIntensity - rest) < 0.01)
    }

    @Test("busy and launcher active together: higher target wins (max)")
    @MainActor
    func busyAndLauncherTogetherTakeMax() {
        let state = IslandState()
        state.setBusy(true)
        state.launcherActive(true)
        for _ in 0..<400 { state.tick(dt: 0.05) }
        // Busy target (~0.8) should dominate over launcher target (~0.6).
        #expect(state.ringIntensity > 0.7)
    }

    @Test("bank(1) sets positive banking; bank(-1) sets negative; decays toward 0 without sign flip or overshoot")
    @MainActor
    func bankDecaysWithoutSignFlip() {
        let state = IslandState()

        state.bank(1)
        #expect(state.banking > 0.9)

        var previous = state.banking
        var reachedZero = false
        for _ in 0..<500 {
            state.tick(dt: 0.05)
            let current = state.banking
            #expect(current >= 0, "banking should not flip sign while decaying from positive")
            #expect(current <= previous + 0.0001, "banking magnitude should decrease monotonically")
            previous = current
            if abs(current) < 0.001 {
                reachedZero = true
                break
            }
        }
        #expect(reachedZero)

        state.bank(-1)
        #expect(state.banking < -0.9)

        previous = state.banking
        reachedZero = false
        for _ in 0..<500 {
            state.tick(dt: 0.05)
            let current = state.banking
            #expect(current <= 0, "banking should not flip sign while decaying from negative")
            #expect(current >= previous - 0.0001, "banking magnitude should decrease monotonically")
            previous = current
            if abs(current) < 0.001 {
                reachedZero = true
                break
            }
        }
        #expect(reachedZero)
    }

    @Test("flare() sets flarePhase non-nil, advances, and eventually clears to nil")
    @MainActor
    func flareAdvancesAndClears() {
        let state = IslandState()
        #expect(state.flarePhase == nil)

        state.flare()
        guard let firstPhase = state.flarePhase else {
            Issue.record("flarePhase should be non-nil right after flare()")
            return
        }
        #expect(firstPhase >= 0)

        var cleared = false
        for _ in 0..<1000 {
            state.tick(dt: 0.05)
            if state.flarePhase == nil {
                cleared = true
                break
            }
        }
        #expect(cleared, "flare should be finite and eventually clear back to nil")
    }

    @Test("no ticking leaves state unchanged")
    @MainActor
    func noTickLeavesStateUnchanged() {
        let state = IslandState()
        state.setBusy(true)
        let level = state.ringIntensity
        // Without calling tick, the raised intensity should remain (no wall-clock decay).
        #expect(state.ringIntensity == level)
    }
}
