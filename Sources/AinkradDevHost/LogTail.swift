import Foundation
import OSLog

/// Streams display-ready log lines for the Dev Host's log pane, merging two
/// sources behind one `stream(subsystem:)` surface:
///
/// 1. **Lifecycle events** — "loaded", "rejected: <reason>", "reloaded" —
///    driven by `DevHostModel`'s state transitions. This side is INJECTED
///    (`lifecycleEvents: AsyncStream<LifecycleEvent>`) rather than read from
///    anywhere real, which is what makes `LogTailTests` deterministic: a
///    test feeds a finite, hand-built sequence of events and finishes the
///    stream itself — no live log store, no real sleeps, no unbounded await.
///
/// 2. **The real plugin subsystem's os_log output** — read via `OSLogStore`
///    for the given subsystem (see `AinkradHostRuntime.Log`, subsystem
///    `com.ainkrad.app`). `OSLogStore` requires the live system log store
///    (and, off-Mac-App-Store, appropriate entitlements) and is NOT
///    deterministically unit-testable, so it's injected too
///    (`readSystemLog`) with a real default the running app uses and tests
///    override with an already-finished empty stream.
struct LogTail {
    /// A Dev Host plugin-lifecycle transition worth showing in the log pane.
    enum LifecycleEvent: Equatable {
        case loaded(String)
        case rejected(reason: String)
        case reloaded
    }

    private let lifecycleEvents: AsyncStream<LifecycleEvent>
    private let readSystemLog: (String) -> AsyncStream<String>

    init(
        lifecycleEvents: AsyncStream<LifecycleEvent>,
        readSystemLog: @escaping (String) -> AsyncStream<String> = LogTail.systemLogStream
    ) {
        self.lifecycleEvents = lifecycleEvents
        self.readSystemLog = readSystemLog
    }

    /// Pure formatter — kept separate from streaming so it (and its exact
    /// output strings) can be asserted directly, with no `AsyncStream`
    /// machinery involved.
    static func line(for event: LifecycleEvent) -> String {
        switch event {
        case .loaded(let id):
            return "loaded: \(id)"
        case .rejected(let reason):
            return "rejected: \(reason)"
        case .reloaded:
            return "reloaded"
        }
    }

    /// Merges the lifecycle-line stream with the system-log tail for
    /// `subsystem` into one line-per-event `AsyncStream`. Finishes once BOTH
    /// sources finish; cancelling the returned stream (its consumer walking
    /// away) cancels both underlying reads.
    func stream(subsystem: String) -> AsyncStream<String> {
        let lifecycleEvents = self.lifecycleEvents
        let systemLog = readSystemLog(subsystem)
        return AsyncStream { continuation in
            let task = Task {
                async let lifecycleDone: Void = {
                    for await event in lifecycleEvents {
                        continuation.yield(LogTail.line(for: event))
                    }
                }()
                async let systemLogDone: Void = {
                    for await line in systemLog {
                        continuation.yield(line)
                    }
                }()
                _ = await (lifecycleDone, systemLogDone)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Real `OSLogStore` tail for `subsystem`: reads entries since process
    /// launch and yields their composed messages, oldest first. Best-effort
    /// — any failure to open the store (e.g. missing entitlement) yields
    /// nothing rather than crashing the Dev Host.
    private static func systemLogStream(subsystem: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                defer { continuation.finish() }
                guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return }
                let position = store.position(timeIntervalSinceLatestBoot: 0)
                guard let entries = try? store.getEntries(at: position) else { return }
                for entry in entries {
                    if Task.isCancelled { return }
                    guard let logEntry = entry as? OSLogEntryLog, logEntry.subsystem == subsystem else { continue }
                    continuation.yield(logEntry.composedMessage)
                }
            }
        }
    }
}
