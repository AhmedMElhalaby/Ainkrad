/// How the Launcher (⌘K) lays out apps — a vertical list (spotlight-style,
/// the default) or a grid of icon tiles. Toggled in Settings → General.
enum LauncherViewMode: String, Codable, CaseIterable, Sendable {
    case list
    case grid
    var label: String { self == .list ? "List" : "Grid" }
}

/// App-wide settings persisted through `SettingsStore`. `theme` defaults to
/// `.neonBlue` on first launch (see ADR-0006 Theming Approach). Decoding
/// tolerates payloads written before/after fields changed — a missing `theme`
/// falls back to the default.
struct GlobalSettings: PersistableDocument {
    static let documentID = "global-settings"
    var theme: Theme = .neonBlue
    var appIconChoice: AppIconChoice = .auto
    var appIconAppearance: AppIconAppearance = .system
    var launcherViewMode: LauncherViewMode = .list
    var confirmBeforeQuit: Bool = true
    var uiFontScale: UIFontScale = .medium
    var uiFontFamily: UIFontFamily = .exo2
    /// A user-picked accent override, as a 6-digit RRGGBB hex string (no
    /// `#`). `nil` means "use the current theme's accent" — see AIN-143.
    var accentColorHex: String? = nil
    /// Shows the full-screen status bar (clock/network/battery) in the top
    /// title strip while in full-screen — see AIN-109. Has no effect in
    /// windowed mode.
    var showFullScreenStatusBar: Bool = true
    /// Whether UI sound effects (open/close/install/etc — see AIN-108) play
    /// at all. Muting takes effect immediately, on the very next sound.
    var soundEnabled: Bool = true
    /// Playback volume (0...1) for UI sound effects — see AIN-108.
    var soundVolume: Double = 0.7
    /// Per-event enable switches, keyed by `UISound.rawValue`. A missing key
    /// means "enabled" — only explicit opt-outs are stored, so legacy docs and
    /// future events need no migration.
    var soundEventEnabled: [String: Bool] = [:]
    /// Per-event effect overrides, keyed by `UISound.rawValue`, valued by the
    /// chosen effect's `UISound.rawValue`. A missing key means "play the
    /// event's own sound". An unknown value (e.g. an effect removed in a later
    /// build) is ignored at read time and falls back to the event's own sound.
    var soundEventEffects: [String: String] = [:]
    /// Master switch for the ambient sky's motion (Settings → Living Sky).
    /// Off freezes every effect in place; the scene stays, the motion stops.
    var skyMotionEnabled: Bool = true
    /// Ambient-sky animation speed multiplier, clamped by `SkySettingsStore`
    /// to 0.5…1.5.
    var skyMotionSpeed: Double = 1.0
    /// Per-effect switches, keyed by `SkyEffect.rawValue`. A missing key
    /// means "enabled" — only explicit opt-outs are stored, so legacy docs
    /// and future effects need no migration.
    var skyEffectEnabled: [String: Bool] = [:]
    /// Background opacity (0.3…1.0) of the summonable HUD overlays
    /// (Launcher / Settings / App Store / Workspace Overview / Quit). Below 1
    /// the blurred workspace behind shows through the panel.
    var overlayBackgroundOpacity: Double = 0.94
    /// Frost the overlay panel with a blur material behind its tint.
    var overlayBlurEnabled: Bool = true
    /// AINKRAD-controlled motion preference, independent of the macOS
    /// system-level Reduce Motion toggle. Default false = motion on.
    var uiReduceMotion: Bool = false

    init(theme: Theme = .neonBlue,
         appIconChoice: AppIconChoice = .auto,
         appIconAppearance: AppIconAppearance = .system,
         launcherViewMode: LauncherViewMode = .list,
         confirmBeforeQuit: Bool = true,
         uiFontScale: UIFontScale = .medium,
         uiFontFamily: UIFontFamily = .exo2,
         accentColorHex: String? = nil,
         showFullScreenStatusBar: Bool = true,
         soundEnabled: Bool = true,
         soundVolume: Double = 0.7,
         soundEventEnabled: [String: Bool] = [:],
         soundEventEffects: [String: String] = [:],
         skyMotionEnabled: Bool = true,
         skyMotionSpeed: Double = 1.0,
         skyEffectEnabled: [String: Bool] = [:],
         overlayBackgroundOpacity: Double = 0.94,
         overlayBlurEnabled: Bool = true,
         uiReduceMotion: Bool = false) {
        self.theme = theme
        self.appIconChoice = appIconChoice
        self.appIconAppearance = appIconAppearance
        self.launcherViewMode = launcherViewMode
        self.confirmBeforeQuit = confirmBeforeQuit
        self.uiFontScale = uiFontScale
        self.uiFontFamily = uiFontFamily
        self.accentColorHex = accentColorHex
        self.showFullScreenStatusBar = showFullScreenStatusBar
        self.soundEnabled = soundEnabled
        self.soundVolume = soundVolume
        self.soundEventEnabled = soundEventEnabled
        self.soundEventEffects = soundEventEffects
        self.skyMotionEnabled = skyMotionEnabled
        self.skyMotionSpeed = skyMotionSpeed
        self.skyEffectEnabled = skyEffectEnabled
        self.overlayBackgroundOpacity = overlayBackgroundOpacity
        self.overlayBlurEnabled = overlayBlurEnabled
        self.uiReduceMotion = uiReduceMotion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .neonBlue
        appIconChoice = try container.decodeIfPresent(AppIconChoice.self, forKey: .appIconChoice) ?? .auto
        appIconAppearance = try container.decodeIfPresent(AppIconAppearance.self, forKey: .appIconAppearance) ?? .system
        launcherViewMode = try container.decodeIfPresent(LauncherViewMode.self, forKey: .launcherViewMode) ?? .list
        confirmBeforeQuit = try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeQuit) ?? true
        uiFontScale = try container.decodeIfPresent(UIFontScale.self, forKey: .uiFontScale) ?? .medium
        uiFontFamily = try container.decodeIfPresent(UIFontFamily.self, forKey: .uiFontFamily) ?? .exo2
        accentColorHex = try container.decodeIfPresent(String.self, forKey: .accentColorHex)
        showFullScreenStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showFullScreenStatusBar) ?? true
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        soundVolume = try container.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.7
        soundEventEnabled = try container.decodeIfPresent([String: Bool].self, forKey: .soundEventEnabled) ?? [:]
        soundEventEffects = try container.decodeIfPresent([String: String].self, forKey: .soundEventEffects) ?? [:]
        skyMotionEnabled = try container.decodeIfPresent(Bool.self, forKey: .skyMotionEnabled) ?? true
        skyMotionSpeed = try container.decodeIfPresent(Double.self, forKey: .skyMotionSpeed) ?? 1.0
        skyEffectEnabled = try container.decodeIfPresent([String: Bool].self, forKey: .skyEffectEnabled) ?? [:]
        overlayBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .overlayBackgroundOpacity) ?? 0.94
        overlayBlurEnabled = try container.decodeIfPresent(Bool.self, forKey: .overlayBlurEnabled) ?? true
        uiReduceMotion = try container.decodeIfPresent(Bool.self, forKey: .uiReduceMotion) ?? false
    }
}
