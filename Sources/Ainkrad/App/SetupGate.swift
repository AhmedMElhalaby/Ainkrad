import AppKit

/// The hardcoded workspace-navigation chords — ⌘1-⌘9, ⌘arrows and ⌘⌥arrows —
/// expressed as pure key/modifier predicates.
///
/// These exist so `SetupGate` and the branches in `KeyboardShortcutMonitor.handle`
/// that actually perform them cannot disagree about what a workspace chord is:
/// both ask the same function. Only the key/modifier condition lives here; the
/// overlay-presentation guards (`!isSetupPresented`, `!isLauncherPresented`, …)
/// stay at the call site, because they are about *when* to perform a chord, not
/// about which chords exist.
enum WorkspaceChord {
    enum CycleDirection { case previous, next }

    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124
    private static let downArrow: UInt16 = 125
    private static let upArrow: UInt16 = 126

    /// ⌘⌥←/→ — cycle to the previous/next workspace.
    static func cycleDirection(keyCode: UInt16, command: Bool, option: Bool) -> CycleDirection? {
        guard command, option else { return nil }
        switch keyCode {
        case leftArrow: return .previous
        case rightArrow: return .next
        default: return nil
        }
    }

    /// ⌘arrows move pane focus, ⌘⇧arrows resize — never with ⌥ held, which is
    /// the workspace-cycle chord above.
    static func paneDirection(keyCode: UInt16, command: Bool, option: Bool) -> PaneDirection? {
        guard command, !option else { return nil }
        switch keyCode {
        case leftArrow: return .left
        case rightArrow: return .right
        case downArrow: return .down
        case upArrow: return .up
        default: return nil
        }
    }

    /// ⌘1-⌘9 — direct jump to a workspace. `characters` is
    /// `charactersIgnoringModifiers`; the index returned is zero-based.
    static func workspaceIndex(characters: String?, command: Bool, shift: Bool) -> Int? {
        guard command, !shift, let characters, let number = Int(characters),
              (1...9).contains(number) else { return nil }
        return number - 1
    }

    /// Whether this keystroke is one of the above — the set `SetupGate` blocks
    /// on top of the registered `ShortcutAction` bindings.
    static func matches(keyCode: UInt16, characters: String?, command: Bool,
                        option: Bool, shift: Bool) -> Bool {
        cycleDirection(keyCode: keyCode, command: command, option: option) != nil
            || paneDirection(keyCode: keyCode, command: command, option: option) != nil
            || workspaceIndex(characters: characters, command: command, shift: shift) != nil
    }
}

/// While first-run setup is presented the workspace behind the gate must be
/// unreachable — but the overlay owns focus, so its text fields must still
/// receive keys.
///
/// The rule is therefore *pass everything, swallow the workspace shortcuts*,
/// not the reverse. An earlier version swallowed every keystroke, which left
/// every text field in the wizard inert: the user could focus a field, watch
/// the caret blink, and type nothing. Four of eight steps were unusable and
/// the Providers step became an inescapable trap for anyone without a Claude
/// subscription.
///
/// The blocked set is exactly (a) any registered `ShortcutAction` binding —
/// which is how ⌘K and ⌘, stay blocked — and (b) the hardcoded
/// `WorkspaceChord`s. Both are resolved by `handle` and passed in, so this
/// decision stays pure and testable: `handle` takes an `NSEvent`, which a unit
/// test cannot meaningfully synthesise, but this can be called directly.
///
/// ⌘H/⌘M/⌘W now reach the system. That is deliberate: hiding or minimising
/// during setup is harmless, and the gate re-raises on the next launch.
///
/// Two unconditional exemptions keep the gate a gate rather than a trap:
///
/// 1. **⌘Q always passes,** matched by CHARACTER and never by key code — "q"
///    is keyCode 39 on Dvorak and 0 on AZERTY. This monitor runs BEFORE the
///    menu bar's key equivalents, so swallowing ⌘Q would stop it ever reaching
///    `NSApp.terminate` → `AinkradAppDelegate` → `QuitCoordinator`.
/// 2. **Return / Enter / Escape pass while the quit confirmation is showing.**
///    `QuitConfirmationView` drives Quit and Cancel off `.defaultAction`,
///    `.cancelAction` and `.onKeyPress(.escape)`, all of which need the keyDown
///    to reach SwiftUI. Without this, ⌘Q raises a dialog only the mouse can
///    answer — the same trap one level down.
enum SetupGate {
    /// Virtual key codes the quit confirmation needs. Escape, Return and keypad
    /// Enter occupy the same physical position on every layout, so matching them
    /// by key code is correct and layout-independent.
    private static let returnKey: UInt16 = 36
    private static let keypadEnter: UInt16 = 76
    private static let escape: UInt16 = 53

    /// Whether the first-run gate goes up at LAUNCH.
    ///
    /// Two reasons, and they are different: no Home has been chosen yet
    /// (`provisionalHome`), or a real Home exists whose setup never finished —
    /// a force-quit mid-wizard — or which owes steps added in a newer
    /// `setupVersion` (`!setupIsComplete`).
    ///
    /// This is a launch-time decision only. It does NOT contradict the wizard's
    /// mid-session lowering (`SetupReseat.Outcome.alreadyConfigured`, and
    /// `SetupDoneStepView.finish()`): both lower the gate only once a completed
    /// marker at the current version exists in the adopted Home's store, which
    /// is exactly the state that makes `setupIsComplete` true here on the next
    /// launch. Read this at boot against the freshly bootstrapped environment's
    /// persistence; never re-evaluate it mid-session, where it would race the
    /// swap and re-raise a gate the user has legitimately cleared.
    static func raisedAtLaunch(provisionalHome: Bool, setupIsComplete: Bool) -> Bool {
        provisionalHome || !setupIsComplete
    }

    /// `true` when the monitor must consume this keystroke WITHOUT performing
    /// anything — it blocks the action, it does not run it. `false` means "not
    /// the gate's business": the gate is down, this is an exempt key, or it is
    /// ordinary input the focused overlay should receive.
    ///
    /// `characters` is `charactersIgnoringModifiers`. ⌘Q is matched on the
    /// CHARACTER, not the key code, and that is load-bearing: the key producing
    /// "q" is keyCode 12 only on QWERTY — it is 39 on Dvorak and 0 on AZERTY.
    /// AppKit matches the Quit key equivalent by character too, so matching by
    /// key code here would swallow the real ⌘Q on those layouts (trapping the
    /// user in the wizard) while letting an inert physical key through.
    static func swallows(
        isSetupPresented: Bool,
        isConfirmingQuit: Bool,
        isRegisteredShortcut: Bool,
        isWorkspaceChord: Bool,
        command: Bool,
        characters: String?,
        keyCode: UInt16
    ) -> Bool {
        guard isSetupPresented else { return false }
        if command, characters?.lowercased() == "q" { return false }
        if isConfirmingQuit, [returnKey, keypadEnter, escape].contains(keyCode) { return false }
        return isRegisteredShortcut || isWorkspaceChord
    }
}
