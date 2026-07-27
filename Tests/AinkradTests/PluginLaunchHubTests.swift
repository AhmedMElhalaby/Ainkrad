import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("PluginLaunchHub")
@MainActor
struct PluginLaunchHubTests {
    @Test("payload is delivered to the target app exactly once")
    func deliverOnce() {
        let hub = PluginLaunchHub()
        hub.enqueue(target: "terminal", payload: "{\"kind\":\"ssh\"}")
        #expect(hub.takePending(for: "terminal") == "{\"kind\":\"ssh\"}")
        #expect(hub.takePending(for: "terminal") == nil)          // consumed
    }

    @Test("payloads are isolated per target app")
    func perApp() {
        let hub = PluginLaunchHub()
        hub.enqueue(target: "terminal", payload: "A")
        #expect(hub.takePending(for: "leyline") == nil)
        #expect(hub.takePending(for: "terminal") == "A")
    }

    @Test("requestOpen fires the wired handler with the app id")
    func requestOpenFires() {
        let hub = PluginLaunchHub()
        var opened: [String] = []
        hub.setOpenHandler { opened.append($0) }
        hub.requestOpen("terminal")
        #expect(opened == ["terminal"])
    }

    @Test("open via the facade enqueues then requests open")
    func facade() {
        let hub = PluginLaunchHub()
        var opened: [String] = []
        hub.setOpenHandler { opened.append($0) }
        let launcher = HostAppLauncher(appID: "leyline", hub: hub)
        launcher.open(appID: "terminal", payload: "P")
        #expect(opened == ["terminal"])
        let terminalSide = HostAppLauncher(appID: "terminal", hub: hub)
        #expect(terminalSide.takePendingLaunch() == "P")
    }
}
