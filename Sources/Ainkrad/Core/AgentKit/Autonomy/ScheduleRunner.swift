import Foundation

/// Fires time-triggered schedules. A single `tick` coalesces any missed window
/// into one run (no double-fire after sleep) and never silently drops a due run.
@MainActor
final class ScheduleRunner {
    private let store: ScheduleStore
    private let runs: RunManager
    private let calendar: Calendar
    private var timer: Timer?

    init(store: ScheduleStore, runs: RunManager, calendar: Calendar = .current) {
        self.store = store
        self.runs = runs
        self.calendar = calendar
    }

    @discardableResult
    func tick(now: Date) -> [UUID] {
        var fired: [UUID] = []
        for schedule in store.schedules where schedule.enabled {
            guard case .time(let cron) = schedule.trigger else { continue }
            // A schedule that has never fired has no real anchor to catch up
            // from — anchoring to the Unix epoch would make `nextFireDate`
            // return the pattern's very first historical occurrence, which is
            // always `<= now` and would fire the schedule immediately on its
            // first tick regardless of the actual time of day. Anchor an
            // unfired schedule to the start of `now`'s day instead: it still
            // catches up on a due time already passed earlier today, but
            // doesn't treat all of history as a missed window.
            let since = schedule.lastFired ?? calendar.startOfDay(for: now)
            guard let due = cron.nextFireDate(after: since, calendar: calendar), due <= now else { continue }
            if due < now {
                // The window between `since` and `now` may contain multiple due
                // instants (e.g. app asleep across days). Coalesce them into a
                // single run rather than backfilling one per missed instant.
                print("ScheduleRunner: coalescing missed window for schedule \(schedule.id) — due \(due), firing at \(now)")
            }
            let run = runs.enqueue(prompt: schedule.prompt, origin: .schedule)
            store.recordFired(schedule.id, runID: run.id, date: now)   // now, not `due`, so the window coalesces
            fired.append(schedule.id)
        }
        return fired
    }

    func start() {
        stop()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(now: Date()) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }
}
