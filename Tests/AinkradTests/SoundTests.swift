import Testing
import Foundation
@testable import Ainkrad
import AinkradHostRuntime

struct UISoundTests {
    @Test("resourceName is a stable, centralized mapping to the bundled wav base-name")
    func resourceName() {
        #expect(UISound.appLaunch.resourceName == "appLaunch")
        #expect(UISound.appQuit.resourceName == "appQuit")
        #expect(UISound.overlayOpen.resourceName == "overlayOpen")
        #expect(UISound.overlayClose.resourceName == "overlayClose")
        #expect(UISound.appOpen.resourceName == "appOpen")
        #expect(UISound.appClose.resourceName == "appClose")
        #expect(UISound.workspaceSwitch.resourceName == "workspaceSwitch")
        #expect(UISound.focusMode.resourceName == "focusMode")
        #expect(UISound.install.resourceName == "install")
        #expect(UISound.uninstall.resourceName == "uninstall")
        #expect(UISound.toggle.resourceName == "toggle")
        #expect(UISound.confirm.resourceName == "confirm")
        #expect(UISound.error.resourceName == "error")
    }

    @Test("allCases covers exactly the expected set of events, no more no less")
    func allCasesIsExpectedSet() {
        let expected: Set<UISound> = [
            .appLaunch, .appQuit, .overlayOpen, .overlayClose,
            .appOpen, .appClose, .workspaceSwitch, .focusMode,
            .install, .uninstall, .toggle, .confirm, .error,
        ]
        #expect(Set(UISound.allCases) == expected)
    }

    @Test("every UISound's wav exists in the main bundle, tolerant if the test bundle can't see app resources")
    func bundledAssetsExist() {
        for sound in UISound.allCases {
            let url = Bundle.main.url(forResource: sound.resourceName, withExtension: "wav")
            if Bundle.main.url(forResource: UISound.appLaunch.resourceName, withExtension: "wav") == nil {
                // The test bundle isn't the app bundle — resources aren't visible here; skip.
                continue
            }
            #expect(url != nil, "missing \(sound.resourceName).wav")
        }
    }
}

struct GlobalSettingsSoundTests {
    @Test("fresh defaults: sound enabled, volume 0.7")
    func defaults() {
        let s = GlobalSettings()
        #expect(s.soundEnabled == true)
        #expect(s.soundVolume == 0.7)
    }

    @Test("round-trips both fields")
    func roundTrip() throws {
        var s = GlobalSettings()
        s.soundEnabled = false
        s.soundVolume = 0.35
        let back = try JSONDecoder().decode(GlobalSettings.self, from: try JSONEncoder().encode(s))
        #expect(back.soundEnabled == false)
        #expect(back.soundVolume == 0.35)
    }

    @Test("a legacy doc without sound keys decodes with defaults")
    func legacyDecodes() throws {
        let legacy = Data(#"{"theme":"neonBlue"}"#.utf8)
        let s = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(s.soundEnabled == true)
        #expect(s.soundVolume == 0.7)
    }
}

@MainActor
private final class FakeSoundSettings: SoundSettingsProviding {
    var soundEnabled: Bool
    var soundVolume: Double
    init(soundEnabled: Bool = true, soundVolume: Double = 0.7) {
        self.soundEnabled = soundEnabled
        self.soundVolume = soundVolume
    }
}

@MainActor
private final class FakeAudioPlayback: AudioPlayback {
    var volume: Float = 1.0
    var currentTime: TimeInterval = 0
    private(set) var playCallCount = 0
    func play() -> Bool {
        playCallCount += 1
        return true
    }
}

@MainActor
struct SoundEngineEnabledGateTests {
    @Test("play does NOT invoke playback when soundEnabled is false")
    func mutedDoesNotPlay() {
        let settings = FakeSoundSettings(soundEnabled: false)
        let token = FakeAudioPlayback()
        let engine = SoundEngine(settings: settings, players: [.confirm: token])
        engine.play(.confirm)
        #expect(token.playCallCount == 0)
    }

    @Test("play DOES invoke playback when soundEnabled is true")
    func enabledPlays() {
        let settings = FakeSoundSettings(soundEnabled: true)
        let token = FakeAudioPlayback()
        let engine = SoundEngine(settings: settings, players: [.confirm: token])
        engine.play(.confirm)
        #expect(token.playCallCount == 1)
    }

    @Test("toggling settings off after construction mutes subsequent play calls")
    func muteTakesEffectImmediately() {
        let settings = FakeSoundSettings(soundEnabled: true)
        let token = FakeAudioPlayback()
        let engine = SoundEngine(settings: settings, players: [.confirm: token])
        engine.play(.confirm)
        settings.soundEnabled = false
        engine.play(.confirm)
        #expect(token.playCallCount == 1)   // only the first call went through
    }

    @Test("play applies the configured volume to the underlying player")
    func appliesVolume() {
        let settings = FakeSoundSettings(soundEnabled: true, soundVolume: 0.42)
        let token = FakeAudioPlayback()
        let engine = SoundEngine(settings: settings, players: [.confirm: token])
        engine.play(.confirm)
        #expect(token.volume == Float(0.42))
    }

    @Test("play is a no-op for a sound with no loaded player (never crashes)")
    func missingPlayerIsNoOp() {
        let settings = FakeSoundSettings(soundEnabled: true)
        let engine = SoundEngine(settings: settings, players: [:])
        engine.play(.appLaunch)   // should not crash
    }
}

@MainActor
private final class FakePerEventSoundSettings: SoundSettingsProviding {
    var soundEnabled: Bool = true
    var soundVolume: Double = 0.7
    var disabledEvents: Set<UISound> = []
    var effectOverrides: [UISound: UISound] = [:]

    func isEventEnabled(_ event: UISound) -> Bool { !disabledEvents.contains(event) }
    func effect(for event: UISound) -> UISound { effectOverrides[event] ?? event }
}

@MainActor
struct SoundEnginePerEventTests {
    @Test("a disabled event does not play even while the master switch is on")
    func disabledEventIsSilent() {
        let settings = FakePerEventSoundSettings()
        settings.disabledEvents = [.focusMode]
        let token = FakeAudioPlayback()
        let engine = SoundEngine(settings: settings, players: [.focusMode: token])
        engine.play(.focusMode)
        #expect(token.playCallCount == 0)
    }

    @Test("an effect override plays the chosen asset, not the event's own")
    func effectOverrideRemaps() {
        let settings = FakePerEventSoundSettings()
        settings.effectOverrides = [.focusMode: .confirm]
        let own = FakeAudioPlayback()
        let chosen = FakeAudioPlayback()
        let engine = SoundEngine(settings: settings, players: [.focusMode: own, .confirm: chosen])
        engine.play(.focusMode)
        #expect(own.playCallCount == 0)
        #expect(chosen.playCallCount == 1)
    }

    @Test("preview bypasses the per-event enable gate but honors the master switch")
    func previewBypassesEventGateOnly() {
        let settings = FakePerEventSoundSettings()
        settings.disabledEvents = [.focusMode]
        let token = FakeAudioPlayback()
        let engine = SoundEngine(settings: settings, players: [.focusMode: token])

        engine.preview(.focusMode)
        #expect(token.playCallCount == 1)   // disabled event still auditions

        settings.soundEnabled = false
        engine.preview(.focusMode)
        #expect(token.playCallCount == 1)   // master mute silences previews too
    }

    @Test("conformers without per-event state default to enabled + own sound")
    func protocolDefaults() {
        let settings = FakeSoundSettings()
        #expect(settings.isEventEnabled(.focusMode) == true)
        #expect(settings.effect(for: .focusMode) == .focusMode)
    }
}

struct GlobalSettingsPerEventSoundTests {
    @Test("fresh defaults: no per-event opt-outs, no effect overrides")
    func defaults() {
        let s = GlobalSettings()
        #expect(s.soundEventEnabled.isEmpty)
        #expect(s.soundEventEffects.isEmpty)
    }

    @Test("round-trips per-event maps")
    func roundTrip() throws {
        var s = GlobalSettings()
        s.soundEventEnabled = ["focusMode": false]
        s.soundEventEffects = ["appOpen": "confirm"]
        let back = try JSONDecoder().decode(GlobalSettings.self, from: try JSONEncoder().encode(s))
        #expect(back.soundEventEnabled == ["focusMode": false])
        #expect(back.soundEventEffects == ["appOpen": "confirm"])
    }

    @Test("a legacy doc without the per-event keys decodes with empty maps")
    func legacyDecodes() throws {
        let legacy = Data(#"{"theme":"neonBlue","soundEnabled":true}"#.utf8)
        let s = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(s.soundEventEnabled.isEmpty)
        #expect(s.soundEventEffects.isEmpty)
    }
}

@MainActor
struct GeneralSettingsStorePerEventTests {
    private func makeStore() -> (GeneralSettingsStore, PersistenceStore) {
        let persistence = InMemoryPersistenceStore()
        return (GeneralSettingsStore(persistence: persistence), persistence)
    }

    @Test("events default to enabled with their own sound")
    func defaults() {
        let (store, _) = makeStore()
        #expect(store.isEventEnabled(.focusMode) == true)
        #expect(store.effect(for: .focusMode) == .focusMode)
    }

    @Test("disabling an event persists; re-enabling removes the stored opt-out")
    func enableDisablePersists() {
        let (store, persistence) = makeStore()

        store.setEventEnabled(false, for: .focusMode)
        #expect(store.isEventEnabled(.focusMode) == false)
        #expect(persistence.load(GlobalSettings.self)?.soundEventEnabled["focusMode"] == false)

        // A fresh store over the same persistence sees the opt-out.
        let reloaded = GeneralSettingsStore(persistence: persistence)
        #expect(reloaded.isEventEnabled(.focusMode) == false)

        store.setEventEnabled(true, for: .focusMode)
        #expect(store.isEventEnabled(.focusMode) == true)
        #expect(persistence.load(GlobalSettings.self)?.soundEventEnabled["focusMode"] == nil)
    }

    @Test("choosing an effect persists; choosing the event's own removes the override")
    func effectChoicePersists() {
        let (store, persistence) = makeStore()

        store.setEffect(.confirm, for: .focusMode)
        #expect(store.effect(for: .focusMode) == .confirm)
        #expect(persistence.load(GlobalSettings.self)?.soundEventEffects["focusMode"] == "confirm")

        let reloaded = GeneralSettingsStore(persistence: persistence)
        #expect(reloaded.effect(for: .focusMode) == .confirm)

        store.setEffect(.focusMode, for: .focusMode)
        #expect(store.effect(for: .focusMode) == .focusMode)
        #expect(persistence.load(GlobalSettings.self)?.soundEventEffects["focusMode"] == nil)
    }

    @Test("an unknown persisted effect value falls back to the event's own sound")
    func unknownEffectFallsBack() {
        let (store, persistence) = makeStore()
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.soundEventEffects = ["focusMode": "not-a-real-sound"]
        persistence.save(settings)

        let reloaded = GeneralSettingsStore(persistence: persistence)
        #expect(reloaded.effect(for: .focusMode) == .focusMode)
        _ = store
    }
}
