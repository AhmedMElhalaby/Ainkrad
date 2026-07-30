import Foundation
import Testing
@testable import Ainkrad

@Suite("Setup motion and sound step")
@MainActor
struct SetupMotionSoundStepTests {
    @Test func choicesApplyImmediately() {
        let t = TestHome.make("motion")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupMotionSound.apply(reduceMotion: true, skyMotion: false, skySpeed: 0.8,
                               soundEnabled: false, volume: 0.4,
                               general: env.generalSettingsStore, sky: env.skySettingsStore)

        #expect(env.generalSettingsStore.uiReduceMotion)
        #expect(!env.skySettingsStore.motionEnabled)
        #expect(env.skySettingsStore.motionSpeed == 0.8)
        #expect(!env.generalSettingsStore.soundEnabled)
        #expect(env.generalSettingsStore.soundVolume == 0.4)
    }

    /// setMotionSpeed clamps to SkySettingsStore.speedRange (0.5...1.5).
    @Test func anOutOfRangeSpeedIsClamped() {
        let t = TestHome.make("motion2")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupMotionSound.apply(reduceMotion: false, skyMotion: true, skySpeed: 9.0,
                               soundEnabled: true, volume: 0.5,
                               general: env.generalSettingsStore, sky: env.skySettingsStore)

        #expect(env.skySettingsStore.motionSpeed == 1.5)
    }
}
