import Foundation
import Testing
@testable import Ainkrad

@Suite("ScheduleStore")
@MainActor
struct ScheduleStoreTests {
    private func schedule(_ name: String) -> AgentSchedule {
        AgentSchedule(id: UUID(), name: name,
            trigger: .time(cron: CronExpression(minutes: [0], hours: [9], daysOfWeek: nil)),
            prompt: "summarize inbox", agentID: nil, enabled: true,
            posture: SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: "workspace-write"))
    }

    @Test func upsertPersists() {
        let p = InMemoryPersistenceStore()
        let store = ScheduleStore(persistence: p)
        let s = schedule("morning")
        store.upsert(s)
        #expect(ScheduleStore(persistence: p).schedules.contains { $0.id == s.id })
    }

    @Test func setEnabledToggles() {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let s = schedule("x"); store.upsert(s)
        store.setEnabled(s.id, false)
        #expect(store.schedules.first { $0.id == s.id }?.enabled == false)
    }

    @Test func recordFiredStampsLastRun() {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let s = schedule("x"); store.upsert(s)
        let runID = UUID(); let when = Date(timeIntervalSince1970: 42)
        store.recordFired(s.id, runID: runID, date: when)
        #expect(store.schedules.first { $0.id == s.id }?.lastRunID == runID)
        #expect(store.schedules.first { $0.id == s.id }?.lastFired == when)
    }

    @Test func codableTriggerRoundTrips() throws {
        let t = ScheduleTrigger.fileChange(path: "/tmp/x", glob: "*.swift")
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(ScheduleTrigger.self, from: data) == t)
    }
}
