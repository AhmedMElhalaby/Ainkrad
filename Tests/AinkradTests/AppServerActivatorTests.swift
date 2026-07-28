import Testing
import Foundation
import AinkradAppKit
@testable import Ainkrad
@testable import AinkradHostRuntime

@MainActor
@Suite("AppServerActivator")
struct AppServerActivatorTests {
    /// A server that answers `initialize` and records how many calls it saw.
    final class Counter { var calls = 0 }

    func makeServer(_ counter: Counter) -> MCPAppServer {
        let server = MCPAppServer(appID: "demo")
        server.addTool(.init(name: "ping", description: "Ping.",
                             schemaJSON: #"{"type":"object"}"#, readOnly: true) { _ in
            counter.calls += 1
            return AgentActionResult(text: "pong", isError: false)
        })
        return server
    }

    let callPing = #"{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"ping","arguments":{}}}"#

    @Test("dispatches straight through when the app is already open", .timeLimit(.minutes(1)))
    func dispatchesWhenOpen() async throws {
        let counter = Counter()
        var openRequests: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in true },
            requestOpen: { openRequests.append($0) },
            availability: { _ in .available })
        let reply = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(reply.contains("pong"))
        #expect(counter.calls == 1)
        #expect(openRequests.isEmpty)   // no launch needed
    }

    @Test("opens a closed app, then dispatches", .timeLimit(.minutes(1)))
    func opensClosedApp() async throws {
        let counter = Counter()
        var opened = false
        var launched: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in opened },
            requestOpen: { _ in opened = true },   // the host opens it synchronously here
            availability: { _ in .available },
            launchTimeout: .seconds(2),
            onLaunch: { launched.append($0) })
        let reply = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(reply.contains("pong"))
        #expect(launched == ["demo"])   // timeline event fired exactly once
    }

    @Test("fails with notInstalled when the app is unknown", .timeLimit(.minutes(1)))
    func failsWhenNotInstalled() async {
        let activator = AppServerActivator(
            servers: [:], isAppOpen: { _ in false }, requestOpen: { _ in },
            availability: { _ in .unknown })
        await #expect(throws: AppDispatchFailure.notInstalled("ghost")) {
            try await activator.dispatch(appID: "ghost", message: callPing)
        }
    }

    @Test("fails with disabled when the app is switched off", .timeLimit(.minutes(1)))
    func failsWhenDisabled() async {
        let counter = Counter()
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in false }, requestOpen: { _ in },
            availability: { _ in .disabled })
        await #expect(throws: AppDispatchFailure.disabled("demo")) {
            try await activator.dispatch(appID: "demo", message: callPing)
        }
    }

    @Test("fails with launchTimedOut when the app never opens", .timeLimit(.minutes(1)))
    func failsWhenLaunchTimesOut() async {
        let counter = Counter()
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in false },          // never becomes open
            requestOpen: { _ in },
            availability: { _ in .available },
            launchTimeout: .milliseconds(200))
        await #expect(throws: AppDispatchFailure.launchTimedOut("demo")) {
            try await activator.dispatch(appID: "demo", message: callPing)
        }
        #expect(counter.calls == 0)
    }
}
