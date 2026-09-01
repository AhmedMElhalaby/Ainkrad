import Testing
import SwiftUI
import AppKit
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal
@testable import Ainkrad

/// Renders Signal surfaces to PNG so they can be looked at during review.
///
/// `ImageRenderer`, not `screencapture`: a window-server capture photographs
/// whatever is being composited at that instant, so a shot taken during an
/// animation or with another window in front comes back wrong and looks like a
/// rendering bug rather than a capture bug. Rendering the view directly is
/// deterministic and needs no window at all.
///
/// Disabled by default - it writes files and exists for the reviewer, not for
/// CI. Run it with `SIGNAL_SNAPSHOT_DIR=/some/dir`.
@MainActor
@Suite("Signal snapshots", .enabled(if: ProcessInfo.processInfo.environment["SIGNAL_SNAPSHOT_DIR"] != nil))
struct SignalSnapshotTests {
    private var outputDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIGNAL_SNAPSHOT_DIR"]!,
            isDirectory: true)
    }

    private func sampleEvents(now: Date) -> [SignalEvent] {
        [
            SignalEvent(timestamp: now.addingTimeInterval(-25), source: .app(appID: "com.ainkrad.raven"),
                        kind: "build.failed", severity: .failure,
                        title: "Build failed",
                        body: "3 errors in SignalStore.swift - linker could not resolve _sqlite3_open",
                        actions: [SignalAction(id: "rerun", label: "Re-run"),
                                  SignalAction(id: "open", label: "Open log")],
                        dedupeKey: "b:main"),
            SignalEvent(timestamp: now.addingTimeInterval(-240), source: .app(appID: "com.ainkrad.quest"),
                        kind: "session.needsInput", severity: .warning,
                        title: "Quest is waiting for you",
                        body: "The agent paused for approval before running a destructive command."),
            SignalEvent(timestamp: now.addingTimeInterval(-3600), source: .host,
                        kind: "run.finished", severity: .success,
                        title: "Run finished",
                        body: "harvest the vault into Wiki articles\nWrote 4 articles, 1 skipped"),
            SignalEvent(timestamp: now.addingTimeInterval(-7200), source: .sage,
                        kind: "memory.indexed", severity: .info,
                        title: "Memory index rebuilt", body: "1,204 notes indexed in 2.1s"),
            SignalEvent(timestamp: now.addingTimeInterval(-90000), source: .app(appID: "com.ainkrad.lore"),
                        kind: "index.completed", severity: .info,
                        title: "Vault index completed"),
        ]
    }

    @Test("render the feed list")
    func renderFeedList() throws {
        let now = Date()
        let events = sampleEvents(now: now)
        let theme = Theme.neonBlue

        let view = SignalFeedList(
            events: events,
            repeatCounts: [events[0].id: 4],
            readIDs: [events[3].id, events[4].id],
            now: now)
            .frame(width: 380, height: 420)
            .background(HostThemeTokens(from: theme).surface)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success,
                warning: theme.tokens.warning,
                danger: theme.tokens.danger))

        let png = try Self.render(view, size: CGSize(width: 380, height: 420))
        let url = outputDirectory.appendingPathComponent("signal-feed-list.png")
        try png.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("render the bell popover")
    func renderBellPopover() throws {
        let now = Date()
        let events = sampleEvents(now: now)
        let theme = Theme.neonBlue

        let view = SignalBellPopover(
            events: events,
            unread: 3,
            repeatCounts: [events[0].id: 4],
            readIDs: [events[3].id, events[4].id],
            now: now)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success,
                warning: theme.tokens.warning,
                danger: theme.tokens.danger))

        let png = try Self.render(view, size: CGSize(width: 380, height: 470))
        try png.write(to: outputDirectory.appendingPathComponent("signal-bell-popover.png"))
    }

    /// Renders through a real `NSHostingView` in an offscreen window.
    ///
    /// `ImageRenderer` was the first choice and produced a blank image: it does
    /// not materialise `ScrollView`/`LazyVStack` content, which is most of what
    /// this surface is. Hosting the view for real and asking the layer to draw
    /// itself renders the actual hierarchy, and still needs no visible window
    /// and no window-server capture.
    static func render(_ view: some View, size: CGSize) throws -> Data {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setIsVisible(false)

        // SwiftUI lays out on the run loop, so give it turns to settle before
        // drawing; without this the lazy rows are still unbuilt.
        hosting.layoutSubtreeIfNeeded()
        for _ in 0..<8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            hosting.layoutSubtreeIfNeeded()
        }

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
                               "could not create a bitmap rep")
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]),
                            "could not encode PNG")
    }
}
