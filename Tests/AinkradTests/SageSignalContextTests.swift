import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Sage reads the Signal feed")
final class SageSignalContextTests {
    private final class NullDeliverer: SignalDeliverer {
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {}
    }
    private struct Ctx: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: true, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    private let deliverer = NullDeliverer()

    private func makeCenter() throws -> (SignalCenter, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        return (SignalCenter(store: try SignalStore(url: url),
                             deliverer: deliverer, contextProvider: Ctx()), url)
    }

    @Test("the context summarizes recent failures first and stays bounded")
    func summaryPrioritizesFailures() throws {
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        for i in 0..<40 {
            center.emit(SignalDraft(kind: "test.event", severity: .info, title: "noise \(i)"),
                        from: .host)
        }
        center.emit(SignalDraft(kind: "build.failed", severity: .failure, title: "THE FAILURE"),
                    from: .app(appID: "raven"))

        let summary = SageSignalContext(center: center).summary()
        #expect(summary.contains("THE FAILURE"))
        #expect(summary.count < 4000, "context is a budget, not a dump")
    }

    @Test("an empty feed produces an empty summary, not a fabricated one")
    func emptyFeed() throws {
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SageSignalContext(center: center).summary().isEmpty)
    }

    @Test("the search tool returns matching events as text")
    func searchTool() throws {
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        center.emit(SignalDraft(kind: "build.failed", severity: .failure,
                                title: "Build failed", body: "linker error"), from: .host)
        let result = SageSignalContext(center: center).search("linker")
        #expect(result.contains("Build failed"))
    }

    @Test("a failure never drops out of the summary because of noise volume")
    func failureSurvivesFlood() throws {
        // The property the ordering exists for. A hundred info rows arriving
        // after a failure must not push it out — "what failed today?" is the
        // question this context is for, and a recency-ordered dump answers it
        // wrongly exactly when there is most to say.
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        center.emit(SignalDraft(kind: "build.failed", severity: .failure, title: "EARLY FAILURE"),
                    from: .app(appID: "raven"))
        for i in 0..<100 {
            center.emit(SignalDraft(kind: "test.event", severity: .info, title: "noise \(i)"),
                        from: .host)
        }
        #expect(SageSignalContext(center: center).summary().contains("EARLY FAILURE"))
    }

    @Test("the summary says which source an event came from")
    func summaryNamesTheSource() throws {
        // Without attribution the assistant cannot answer "what failed" with
        // anything actionable — "Build failed" alone does not say whose build.
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        center.emit(SignalDraft(kind: "sync.failed", severity: .failure, title: "Sync failed"),
                    from: .app(appID: "raven"))
        let summary = SageSignalContext(center: center).summary()
        #expect(summary.lowercased().contains("raven"))
    }

    @Test("search reports finding nothing rather than returning an empty string")
    func searchWithNoMatches() throws {
        // An empty string reads to a model as a tool that failed, and invites
        // it to guess. Saying "no notifications match" is a fact it can use.
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        let result = SageSignalContext(center: center).search("nothing-like-this")
        #expect(!result.isEmpty)
        #expect(result.lowercased().contains("no "))
    }

    @Test("search is bounded too, so one query cannot flood the context")
    func searchIsBounded() throws {
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        for i in 0..<200 {
            center.emit(SignalDraft(kind: "test.event", severity: .info,
                                    title: "linker noise \(i)"), from: .host)
        }
        #expect(SageSignalContext(center: center).search("linker").count < 8000)
    }
    // MARK: - The tool and its late-bound access

    @Test("the tool reports unavailability as a result, not an error")
    func toolBeforeTheFeedExists() async throws {
        // signal_search is assembled before the SignalCenter exists. Throwing
        // here would teach the model the tool is broken and stop it calling
        // later, when the feed is there.
        let tool = SignalSearchTool(access: SignalReadAccess())
        let result = try await tool.execute(.object(["query": .string("anything")]))
        #expect(result.isError == false)
        #expect(result.content.contains("unavailable"))
    }

    @Test("once attached, the tool searches the real feed")
    func toolAfterAttach() async throws {
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        center.emit(SignalDraft(kind: "build.failed", severity: .failure,
                                title: "Build failed", body: "linker error"), from: .host)

        let access = SignalReadAccess()
        access.attach(center)
        let result = try await SignalSearchTool(access: access)
            .execute(.object(["query": .string("linker")]))
        #expect(result.isError == false)
        #expect(result.content.contains("Build failed"))
    }

    @Test("the tool is read-class, so it is gated like a read and cannot mutate")
    func toolIsReadClass() {
        // The permission class is what the approval HUD keys off. A feed
        // reader miscategorised as `.write` would prompt for every question
        // about what failed; one that could mutate should not exist at all.
        #expect(SignalSearchTool(access: SignalReadAccess()).permission == .read)
    }

    @Test("a missing query is a real error, unlike a missing feed")
    func toolRejectsMissingQuery() async {
        // The distinction matters: no feed is a fact about the machine, but a
        // call with no query is a malformed call, and the model should see the
        // difference.
        let tool = SignalSearchTool(access: SignalReadAccess())
        await #expect(throws: (any Error).self) {
            _ = try await tool.execute(.object([:]))
        }
    }
    // MARK: - Found by running against the real feed

    @Test("a recurring problem collapses to one line with a count")
    func recurringCollapses() throws {
        // Seventeen near-identical Raven sync warnings, hours apart, filled the
        // entire summary budget on the real feed. They are separate events, so
        // the store's 60-second dedupe cannot help — but for "what failed
        // today?" they are one fact.
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        for i in 0..<17 {
            center.emit(SignalDraft(kind: "sync.failed", severity: .warning,
                                    title: "Could not sync",
                                    body: "attempt \(i)",
                                    dedupeKey: "attempt-\(i)"),
                        from: .app(appID: "raven"))
        }
        let summary = SageSignalContext(center: center).summary()
        let syncLines = summary.split(separator: "\n").filter { $0.contains("Could not sync") }
        #expect(syncLines.count == 1, "one fact, one line")
        #expect(summary.contains("17x"), "the count is the useful part")
    }

    @Test("collapsing does not hide a DIFFERENT app's failure behind a flood")
    func floodDoesNotCrowdOutOthers() throws {
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        for i in 0..<40 {
            center.emit(SignalDraft(kind: "sync.failed", severity: .warning,
                                    title: "Could not sync", dedupeKey: "a-\(i)"),
                        from: .app(appID: "raven"))
        }
        center.emit(SignalDraft(kind: "build.failed", severity: .failure,
                                title: "QUEST BUILD BROKE"), from: .app(appID: "quest"))
        #expect(SageSignalContext(center: center).summary().contains("QUEST BUILD BROKE"))
    }

    @Test("search matches a KIND, not only title and body")
    func searchMatchesKind() throws {
        // FTS covers title and body only. On the real feed, searching "failed"
        // returned nothing while sync.failed rows sat right there, titled
        // "Could not sync" — and "failed" is the likeliest thing an assistant
        // would search for.
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        center.emit(SignalDraft(kind: "sync.failed", severity: .warning,
                                title: "Could not sync mail"), from: .app(appID: "raven"))
        let result = SageSignalContext(center: center).search("failed")
        #expect(result.contains("Could not sync mail"))
    }

    @Test("a kind match and a text match for one event are not reported twice")
    func kindAndTextMatchDeduplicate() throws {
        let (center, url) = try makeCenter()
        defer { try? FileManager.default.removeItem(at: url) }
        center.emit(SignalDraft(kind: "build.failed", severity: .failure,
                                title: "Build failed"), from: .host)
        let lines = SageSignalContext(center: center).search("failed")
            .split(separator: "\n").filter { $0.contains("Build failed") }
        #expect(lines.count == 1)
    }
}
