import AVFoundation

/// The seam callers use to play UI sounds — lets views/stores trigger sound
/// without knowing about `AVAudioPlayer` or the enabled/volume settings.
@MainActor
protocol SoundPlaying {
    func play(_ sound: UISound)
}

/// The subset of `GeneralSettingsStore` `SoundEngine` needs to decide
/// whether/how loud to play — lets tests substitute a fake without spinning
/// up real persistence, and lets `SoundEngine` read live settings changes
/// (muting takes effect on the very next `play` call).
@MainActor
protocol SoundSettingsProviding {
    var soundEnabled: Bool { get }
    var soundVolume: Double { get }
}

/// A thin seam over `AVAudioPlayer` so the enabled/volume gate in
/// `SoundEngine` is unit-testable without touching real audio playback —
/// `AVAudioPlayer` already has matching members, so the conformance below is
/// free.
@MainActor
protocol AudioPlayback: AnyObject {
    var volume: Float { get set }
    var currentTime: TimeInterval { get set }
    @discardableResult func play() -> Bool
}

extension AVAudioPlayer: AudioPlayback {}

/// Preloads one `AVAudioPlayer` per `UISound` — from a user-data override
/// directory when present (AIN-108 follow-up: lets a user swap in their own,
/// possibly copyrighted, sound pack outside the repo/bundle), else from the
/// app bundle — and plays them on demand, gated by `settings.soundEnabled`
/// and scaled by `settings.soundVolume`. A sound whose asset failed to load
/// (headless/CI, a bundle that doesn't ship `Resources/Sounds/`, or a
/// missing override) is silently skipped — playback is best-effort and must
/// never crash the app.
@MainActor
final class SoundEngine: SoundPlaying {
    private let settings: SoundSettingsProviding
    private var players: [UISound: AudioPlayback]

    /// Production entry point: loads every `UISound`'s wav, preferring
    /// `overrideDirectory/<name>.wav` on disk over `bundle`'s bundled copy.
    /// `bundle` defaults to `.main` (the app bundle); `overrideDirectory`
    /// defaults to `nil` (always use the bundle) — callers that want
    /// overrides (see `AppEnvironment.bootstrap`) pass a real directory,
    /// which need not exist yet (resolution falls back to the bundle).
    init(settings: SoundSettingsProviding, bundle: Bundle = .main, overrideDirectory: URL? = nil) {
        self.settings = settings
        var loaded: [UISound: AudioPlayback] = [:]
        for sound in UISound.allCases {
            guard let url = SoundEngine.resolvedURL(
                    for: sound,
                    overrideDirectory: overrideDirectory,
                    bundle: bundle,
                    fileExists: { FileManager.default.fileExists(atPath: $0.path) }
                  ),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            loaded[sound] = player
        }
        self.players = loaded
    }

    /// Pure override-resolution rule, extracted so it's unit-testable without
    /// touching real disk/bundle state: prefers
    /// `overrideDirectory/<sound.resourceName>.wav` when `fileExists` reports
    /// it present, else falls back to `bundle`'s bundled copy of the same
    /// name, else `nil` (caller skips that sound rather than crashing).
    nonisolated static func resolvedURL(
        for sound: UISound,
        overrideDirectory: URL?,
        bundle: Bundle,
        fileExists: (URL) -> Bool
    ) -> URL? {
        if let overrideDirectory {
            let overrideURL = overrideDirectory.appendingPathComponent("\(sound.resourceName).wav")
            if fileExists(overrideURL) {
                return overrideURL
            }
        }
        return bundle.url(forResource: sound.resourceName, withExtension: "wav")
    }

    /// Test entry point: inject fake playback tokens directly, bypassing
    /// bundle/file loading entirely — this is what makes the enabled-gate
    /// unit-testable (see `SoundTests.swift`).
    init(settings: SoundSettingsProviding, players: [UISound: AudioPlayback]) {
        self.settings = settings
        self.players = players
    }

    func play(_ sound: UISound) {
        guard settings.soundEnabled else { return }
        guard let player = players[sound] else { return }
        player.volume = Float(settings.soundVolume)
        player.currentTime = 0
        player.play()
    }
}
