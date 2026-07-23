import Foundation

/// Fans a batch of `SubagentSpec`s out to a `SubagentRunner` with bounded
/// concurrency and failure isolation.
///
/// - **Bounded concurrency:** at most `maxConcurrent` `run()` calls are ever
///   in flight; the windowed `TaskGroup` below seeds up to the cap and adds
///   one replacement each time a slot frees, so it never spawns all N at once.
/// - **Failure isolation:** `SubagentRunner.run` returns a `SubagentOutcome`
///   rather than throwing, so a failing child can never cancel siblings or
///   propagate out of `spawn`. `spawn` itself has no `throws` and never does.
/// - **Deterministic aggregation:** execution order is concurrency-driven,
///   but the returned array is re-sorted to match the input `specs` order by
///   keying completed outcomes on `spec.id`.
@MainActor
final class SubagentCoordinator {
    private let runner: SubagentRunner
    private let maxConcurrent: Int

    init(runner: SubagentRunner, maxConcurrent: Int = 4) {
        self.runner = runner
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func spawn(_ specs: [SubagentSpec]) async -> [SubagentOutcome] {
        guard !specs.isEmpty else { return [] }
        var byID: [UUID: SubagentOutcome] = [:]
        var iterator = specs.makeIterator()

        await withTaskGroup(of: SubagentOutcome.self) { group in
            func addNext() {
                guard let spec = iterator.next() else { return }
                group.addTask { await self.runOne(spec) }
            }
            for _ in 0..<min(maxConcurrent, specs.count) { addNext() }
            while let outcome = await group.next() {
                byID[outcome.id] = outcome
                addNext()
            }
        }
        // Preserve input order regardless of completion order.
        return specs.compactMap { byID[$0.id] }
    }

    /// Isolation-crossing shim: `addTask`'s closure is nonisolated, so it
    /// hops back to `MainActor` (where `runner` lives) via this method rather
    /// than capturing `runner` directly inside the closure.
    private func runOne(_ spec: SubagentSpec) async -> SubagentOutcome {
        await runner.run(spec)
    }
}
