import Foundation
import Testing
@testable import Ainkrad

@Suite("Setup you step")
@MainActor
struct SetupYouStepTests {
    @Test func profileFactsPersistAndReachTheAgentsMemory() throws {
        let t = TestHome.make("you")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupYou.apply(name: "Ahmed", callMe: "Ahmed", role: "Engineer",
                       timezone: "Africa/Cairo", store: env.userProfileStore)

        #expect(env.userProfileStore.all()["name"] == "Ahmed")
        #expect(env.userProfileStore.all()["role"] == "Engineer")

        // The whole point of reusing this store: the assistant can read it.
        // `MemoryPaths(root: home.shared(.memory))` resolves `.user` to
        // `<memory root>/USER.md` — verified against MemoryFile.user's raw value.
        let userDoc = t.home.shared(.memory).appendingPathComponent("USER.md")
        #expect(FileManager.default.fileExists(atPath: userDoc.path))
        let body = try String(contentsOf: userDoc, encoding: .utf8)
        #expect(body.contains("Ahmed"))
    }

    @Test func blankFieldsAreNotWritten() {
        let t = TestHome.make("you2")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupYou.apply(name: "Ahmed", callMe: "", role: "  ", timezone: "",
                       store: env.userProfileStore)

        #expect(env.userProfileStore.all()["callMe"] == nil)
        #expect(env.userProfileStore.all()["role"] == nil)
    }
}
