import Foundation

/// Event-reactive state for the Living Island home artwork (the "Jarvis"
/// behaviors): ring brightness, workspace-switch banking, and notification
/// flares. Purely a data/animation model — the view samples it each frame
/// via `tick(dt:)` and renders accordingly. No wall-clock or randomness
/// inside this class, so it stays deterministic and testable, and safe to
/// resume/preview without drift.
@MainActor
@Observable
final class IslandState {
    /// Resting ring intensity — the island's idle glow.
    static let restIntensity = 0.35
    /// Target ring intensity while `setBusy(true)` (an agent/long task is running).
    static let busyIntensity = 0.8
    /// Target ring intensity while the Launcher is open.
    static let launcherIntensity = 0.6
    /// Exponential approach rate (per second) toward the current ring target.
    static let ringApproachRate = 4.0

    /// Exponential decay rate (per second) for the banking impulse.
    static let bankingDecayRate = 3.0

    /// Duration (seconds) of a full flare progression, 0...1.
    static let flareDuration = 1.2

    /// 0…1 base energy of the ring/glow. Rest ≈ 0.35.
    private(set) var ringIntensity: Double
    /// Signed −1…1 horizontal workspace-switch impulse; decays to 0.
    private(set) var banking: Double
    /// Transient beacon-flare progress at the spire tip; nil when idle.
    private(set) var flarePhase: Double?

    private var isBusy = false
    private var isLauncherActive = false

    init() {
        self.ringIntensity = Self.restIntensity
        self.banking = 0
        self.flarePhase = nil
    }

    /// Sustained elevated ringIntensity while an agent / long task runs.
    func setBusy(_ busy: Bool) {
        isBusy = busy
        if busy {
            // Snap up immediately so callers observe the raise without
            // needing a tick — the subsequent decay/approach is still
            // driven only by `tick(dt:)`.
            ringIntensity = max(ringIntensity, Self.busyIntensity)
        }
    }

    /// One-shot beacon flare (notifications). Starts flarePhase progression.
    func flare() {
        flarePhase = 0
    }

    /// A decaying horizontal banking impulse (workspace switch).
    func bank(_ direction: Double) {
        banking = max(-1, min(1, direction))
    }

    /// Brighten the ring while the Launcher is open.
    func launcherActive(_ active: Bool) {
        isLauncherActive = active
        if active {
            ringIntensity = max(ringIntensity, Self.launcherIntensity)
        }
    }

    /// Advance decay/animation by dt seconds — called from the view's clock.
    func tick(dt: Double) {
        guard dt > 0 else { return }

        // Ring intensity exponentially approaches whichever target is
        // currently active (rest, busy, or launcher-active — max wins).
        var target = Self.restIntensity
        if isBusy { target = max(target, Self.busyIntensity) }
        if isLauncherActive { target = max(target, Self.launcherIntensity) }

        let ringAlpha = 1 - exp(-Self.ringApproachRate * dt)
        ringIntensity += (target - ringIntensity) * ringAlpha
        // Guard against float drift landing just under rest when neither
        // busy nor launcher is active.
        if !isBusy && !isLauncherActive && ringIntensity < Self.restIntensity {
            ringIntensity = Self.restIntensity
        }

        // Banking decays exponentially toward 0, sign-preserving.
        if banking != 0 {
            let bankAlpha = exp(-Self.bankingDecayRate * dt)
            banking *= bankAlpha
            if abs(banking) < 0.001 {
                banking = 0
            }
        }

        // Flare advances linearly over `flareDuration` then clears.
        if let phase = flarePhase {
            let next = phase + dt / Self.flareDuration
            flarePhase = next >= 1 ? nil : next
        }
    }
}
