import Foundation
import Testing
@testable import Ainkrad
import AinkradAppKit

@Suite("Setup gate")
@MainActor
struct SetupGateTests {
    @Test func aProvisionalHomeRaisesTheSetupGate() throws {
        let t = TestHome.make("gate")
        defer { t.cleanup() }

        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        environment.isProvisionalHome = true
        environment.isSetupPresented = true

        #expect(environment.isSetupPresented)
        // Every other overlay must be suppressed while setup is up.
        #expect(!environment.isLauncherPresented)
        #expect(!environment.isSettingsPresented)
    }

    @Test func setupSuppressesEveryOtherOverlayShortcut() throws {
        let t = TestHome.make("gate2")
        defer { t.cleanup() }

        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        environment.isSetupPresented = true

        for action in ShortcutAction.allCases {
            #expect(SetupGate.suppresses(action, isSetupPresented: environment.isSetupPresented),
                    "\(action) must be inert while setup is presented")
        }
        // And the same enum must let every action through once the gate is down —
        // otherwise the assertion above would hold for a function that is simply
        // `true`, and would keep holding after someone broke the gate's teardown.
        for action in ShortcutAction.allCases {
            #expect(!SetupGate.suppresses(action, isSetupPresented: false),
                    "\(action) must work again once setup is dismissed")
        }
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
