import Observation

/// Every live effect of the ambient sky, each individually switchable in
/// Settings → Living Sky. Raw values are the persistence keys — stable
/// across renames of the display strings.
enum SkyEffect: String, CaseIterable, Identifiable {
    case stars
    case aurora
    case embers
    case shootingStars
    case skyMoments
    case breathingSky
    case horizonMist
    case lightRays
    case fireflies
    case bokeh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stars: return "Drifting stars"
        case .aurora: return "Aurora ribbons"
        case .embers: return "Rising embers"
        case .shootingStars: return "Shooting stars"
        case .skyMoments: return "Rare sky moments"
        case .breathingSky: return "Breathing sky"
        case .horizonMist: return "Horizon mist"
        case .lightRays: return "Light rays"
        case .fireflies: return "Island fireflies"
        case .bokeh: return "Foreground bokeh"
        }
    }

    var effectDescription: String {
        switch self {
        case .stars: return "A starfield in slow, endless drift — twinkling, with occasional glints."
        case .aurora: return "Two soft ribbons of accent light shimmering high in the sky."
        case .embers: return "Tiny sparks rising gently from below."
        case .shootingStars: return "A brief lone streak across the upper sky, about once a minute."
        case .skyMoments: return "Rare events: meteor-shower bursts, a slow comet, aurora surges."
        case .breathingSky: return "The horizon glow slowly swells and relaxes, like the sky inhaling."
        case .horizonMist: return "Faint fog bands sliding sideways near the horizon."
        case .lightRays: return "Soft god-rays fanning up from the sun below the horizon."
        case .fireflies: return "Energy motes drifting upward around the island."
        case .bokeh: return "A few large, out-of-focus orbs floating in the extreme foreground."
        }
    }
}

/// Owns Settings → Living Sky: the master animate switch, the motion speed,
/// and the per-effect switches. Loads from `GlobalSettings` and persists
/// changes while preserving the rest of the document — same load/mutate/save
/// pattern as `GeneralSettingsStore`.
@MainActor
@Observable
final class SkySettingsStore {
    /// The supported animation-speed band.
    static let speedRange = 0.5...1.5

    private(set) var motionEnabled: Bool
    private(set) var motionSpeed: Double
    /// Per-effect switches (missing key = enabled) — only explicit opt-outs
    /// are stored, so legacy docs and future effects need no migration.
    private(set) var effectEnabled: [String: Bool]
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        self.motionEnabled = settings.skyMotionEnabled
        // Clamp at the load boundary too — a hand-edited or future-build
        // payload must not drive the sky clock out of the supported band.
        self.motionSpeed = min(
            max(settings.skyMotionSpeed, Self.speedRange.lowerBound),
            Self.speedRange.upperBound
        )
        self.effectEnabled = settings.skyEffectEnabled
    }

    func isEnabled(_ effect: SkyEffect) -> Bool {
        effectEnabled[effect.rawValue] ?? true
    }

    func setEnabled(_ isOn: Bool, for effect: SkyEffect) {
        // Only explicit opt-outs are stored; enabling removes the key so the
        // persisted doc stays minimal.
        effectEnabled[effect.rawValue] = isOn ? nil : false
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.skyEffectEnabled = effectEnabled
        persistence.save(settings)
    }

    func setMotionEnabled(_ isOn: Bool) {
        motionEnabled = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.skyMotionEnabled = isOn
        persistence.save(settings)
    }

    func setMotionSpeed(_ speed: Double) {
        let clamped = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        motionSpeed = clamped
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.skyMotionSpeed = clamped
        persistence.save(settings)
    }
}
