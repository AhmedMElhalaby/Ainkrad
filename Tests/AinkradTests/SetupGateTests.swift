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

    /// Every chord the monitor can act on: the named `ShortcutAction` bindings
    /// plus the hardcoded checks (⌘1-9, ⌘arrows, ⌘M, ⌘D, ⌥←/→).
    private static let workspaceChords: [(name: String, keyCode: UInt16, command: Bool)] = [
        ("⌘K open launcher", k, true),
        ("⌘⇧N new workspace", n, true),
        ("⌘1 switch workspace", one, true),
        ("⌘← focus pane", leftArrow, true),
        ("⌥← cycle workspace", leftArrow, false),
        ("bare Return", returnKey, false),
        ("bare Escape", escape, false),
    ]

    @Test func theGateSwallowsEveryWorkspaceKeystroke() throws {
        for chord in Self.workspaceChords {
            #expect(SetupGate.swallows(keyCode: chord.keyCode, command: chord.command,
                                       isSetupPresented: true, isConfirmingQuit: false),
                    "\(chord.name) must be inert while setup is presented")
        }
    }

    @Test func theGateSwallowsNothingOnceSetupIsDismissed() throws {
        for chord in Self.workspaceChords {
            #expect(!SetupGate.swallows(keyCode: chord.keyCode, command: chord.command,
                                        isSetupPresented: false, isConfirmingQuit: false),
                    "\(chord.name) must work again once setup is dismissed")
        }
    }

    /// The monitor runs before the menu bar's key equivalents, so swallowing ⌘Q
    /// would stop it ever reaching `NSApp.terminate`. A wizard the user cannot
    /// quit out of is a trap.
    @Test func commandQAlwaysPasses() throws {
        #expect(!SetupGate.swallows(keyCode: Self.q, command: true,
                                    isSetupPresented: true, isConfirmingQuit: false))
        #expect(!SetupGate.swallows(keyCode: Self.q, command: true,
                                    isSetupPresented: true, isConfirmingQuit: true))
        // Bare Q is just a letter — it stays swallowed.
        #expect(SetupGate.swallows(keyCode: Self.q, command: false,
                                   isSetupPresented: true, isConfirmingQuit: false))
    }

    /// `QuitConfirmationView` answers Return/Escape via `.defaultAction`,
    /// `.cancelAction` and `.onKeyPress(.escape)`, all of which need the keyDown
    /// to reach SwiftUI. Otherwise ⌘Q raises a dialog only the mouse can answer.
    @Test func quitConfirmationKeysPassWhileItIsShowing() throws {
        for key in [Self.returnKey, Self.keypadEnter, Self.escape] {
            #expect(!SetupGate.swallows(keyCode: key, command: false,
                                        isSetupPresented: true, isConfirmingQuit: true),
                    "key \(key) must reach the quit confirmation")
            // ...and only while it is showing.
            #expect(SetupGate.swallows(keyCode: key, command: false,
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
        #expect(SetupGate.swallows(keyCode: Self.k, command: true,
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
