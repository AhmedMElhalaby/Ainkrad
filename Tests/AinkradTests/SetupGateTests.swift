import Foundation
import Testing
@testable import Ainkrad
import AinkradAppKit

/// The first-run gate: what it blocks, and the two things it must never block.
///
/// These exercise `SetupGate.swallows` — the decision `KeyboardShortcutMonitor.handle`
/// actually calls. `handle` itself takes an `NSEvent`, which a unit test cannot
/// meaningfully synthesise, so the decision was extracted rather than mocked.
@Suite("Setup gate")
@MainActor
struct SetupGateTests {
    // ANSI virtual key codes, matching `KeyChord.keyLabels`.
    private static let q: UInt16 = 12
    private static let k: UInt16 = 40
    private static let n: UInt16 = 45
    private static let one: UInt16 = 18
    private static let leftArrow: UInt16 = 123
    private static let returnKey: UInt16 = 36
    private static let keypadEnter: UInt16 = 76
    private static let escape: UInt16 = 53
    /// The keyCode that types "q" on Dvorak / AZERTY — deliberately not 12.
    private static let dvorakQ: UInt16 = 39
    private static let azertyQ: UInt16 = 0

    /// Every chord the monitor can act on: the named `ShortcutAction` bindings
    /// plus the hardcoded checks (⌘1-9, ⌘arrows, ⌘M, ⌘D, ⌥←/→).
    private static let workspaceChords: [(name: String, keyCode: UInt16, characters: String?, command: Bool)] = [
        ("⌘K open launcher", k, "k", true),
        ("⌘⇧N new workspace", n, "n", true),
        ("⌘1 switch workspace", one, "1", true),
        ("⌘← focus pane", leftArrow, nil, true),
        ("⌥← cycle workspace", leftArrow, nil, false),
        ("bare Return", returnKey, "\r", false),
        ("bare Escape", escape, "\u{1b}", false),
    ]

    @Test func theGateSwallowsEveryWorkspaceKeystroke() throws {
        for chord in Self.workspaceChords {
            #expect(SetupGate.swallows(keyCode: chord.keyCode, characters: chord.characters,
                                       command: chord.command,
                                       isSetupPresented: true, isConfirmingQuit: false),
                    "\(chord.name) must be inert while setup is presented")
        }
    }

    @Test func theGateSwallowsNothingOnceSetupIsDismissed() throws {
        for chord in Self.workspaceChords {
            #expect(!SetupGate.swallows(keyCode: chord.keyCode, characters: chord.characters,
                                        command: chord.command,
                                        isSetupPresented: false, isConfirmingQuit: false),
                    "\(chord.name) must work again once setup is dismissed")
        }
    }

    /// The monitor runs before the menu bar's key equivalents, so swallowing ⌘Q
    /// would stop it ever reaching `NSApp.terminate`. A wizard the user cannot
    /// quit out of is a trap.
    @Test func commandQAlwaysPasses() throws {
        #expect(!SetupGate.swallows(keyCode: Self.q, characters: "q", command: true,
                                    isSetupPresented: true, isConfirmingQuit: false))
        #expect(!SetupGate.swallows(keyCode: Self.q, characters: "q", command: true,
                                    isSetupPresented: true, isConfirmingQuit: true))
        // Bare Q is just a letter — it stays swallowed.
        #expect(SetupGate.swallows(keyCode: Self.q, characters: "q", command: false,
                                   isSetupPresented: true, isConfirmingQuit: false))
    }

    /// ⌘Q must be matched on the CHARACTER, never the physical key position.
    /// The key that types "q" is keyCode 12 only on QWERTY: it is 39 on Dvorak
    /// and 0 on AZERTY. Matching by key code would swallow the real ⌘Q on those
    /// layouts — trapping the user in the wizard with no keyboard escape — while
    /// letting an inert physical key through.
    @Test func commandQPassesOnNonQwertyLayouts() throws {
        for keyCode in [Self.dvorakQ, Self.azertyQ] {
            #expect(keyCode != Self.q)
            #expect(!SetupGate.swallows(keyCode: keyCode, characters: "q", command: true,
                                        isSetupPresented: true, isConfirmingQuit: false),
                    "⌘Q from keyCode \(keyCode) must still quit")
        }
        // The converse: on those layouts the ANSI-Q POSITION types something else
        // (Dvorak "'", AZERTY "a"), and that is an ordinary key the gate swallows.
        #expect(SetupGate.swallows(keyCode: Self.q, characters: "a", command: true,
                                   isSetupPresented: true, isConfirmingQuit: false))
    }

    /// `QuitConfirmationView` answers Return/Escape via `.defaultAction`,
    /// `.cancelAction` and `.onKeyPress(.escape)`, all of which need the keyDown
    /// to reach SwiftUI. Otherwise ⌘Q raises a dialog only the mouse can answer.
    @Test func quitConfirmationKeysPassWhileItIsShowing() throws {
        for key in [Self.returnKey, Self.keypadEnter, Self.escape] {
            #expect(!SetupGate.swallows(keyCode: key, characters: nil, command: false,
                                        isSetupPresented: true, isConfirmingQuit: true),
                    "key \(key) must reach the quit confirmation")
            // ...and only while it is showing.
            #expect(SetupGate.swallows(keyCode: key, characters: nil, command: false,
                                       isSetupPresented: true, isConfirmingQuit: false))
        }
    }

    @Test func bootingProvisionallyRaisesTheGateAndFlagsTheHome() throws {
        let t = TestHome.make("gate")
        defer { t.cleanup() }

        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        // Defaults: an app booted onto a real Home is not gated.
        #expect(!environment.isSetupPresented)
        #expect(!environment.isProvisionalHome)

        // What `AinkradHostApp.init` does on `.unset`.
        environment.isProvisionalHome = true
        environment.isSetupPresented = true

        // The gate is raised over a workspace nothing else has opened.
        #expect(!environment.isLauncherPresented)
        #expect(!environment.isSettingsPresented)
        #expect(SetupGate.swallows(keyCode: Self.k, characters: "k", command: true,
                                   isSetupPresented: environment.isSetupPresented,
                                   isConfirmingQuit: false))
    }

    @Test func aProvisionalHomeIsNeverPointedAt() throws {
        let home = LaunchHomeResolver.provisionalHome()
        let pointer = AinkradHome.defaultPointerDirectory()
            .appendingPathComponent("home.json")
        // The provisional home must not be the vault any pointer names.
        if let data = try? Data(contentsOf: pointer),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let path = json["path"] as? String {
            #expect(path != home.vaultRoot.path)
        }
        #expect(!FileManager.default.fileExists(
            atPath: home.vaultRoot.appendingPathComponent(".ainkrad-home").path))
        // The invariant the gate exists to protect: a provisional home resolves to
        // a throwaway keychain namespace, so nothing authored may be written yet.
        #expect(home.isProvisional)
    }
}
