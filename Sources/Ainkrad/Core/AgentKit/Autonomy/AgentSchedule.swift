import Foundation

enum ScheduleTrigger: Codable, Equatable, Sendable {
    case time(cron: CronExpression)
    case fileChange(path: String, glob: String?)
    case gitChange(repoPath: String)
    case webhook(id: String)
}

/// The explicit, saved permission/sandbox posture a schedule runs with. Set at
/// creation; the scheduler never escalates beyond it.
struct SavedExecutionPosture: Codable, Equatable, Sendable {
    var permissionMode: String            // AgentPermissionMode.rawValue
    var sandboxProfileID: String?         // PROVISIONAL — projects into Slice 6 AgentExecutionPolicy

    init(permissionMode: String, sandboxProfileID: String? = nil) {
        self.permissionMode = permissionMode
        self.sandboxProfileID = sandboxProfileID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        permissionMode = try c.decodeIfPresent(String.self, forKey: .permissionMode) ?? "ask"
        sandboxProfileID = try c.decodeIfPresent(String.self, forKey: .sandboxProfileID)
    }
}

struct AgentSchedule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var trigger: ScheduleTrigger
    var prompt: String
    var agentID: UUID?
    var enabled: Bool
    var posture: SavedExecutionPosture
    var lastFired: Date?
    var lastRunID: UUID?

    init(id: UUID = UUID(), name: String, trigger: ScheduleTrigger, prompt: String,
         agentID: UUID? = nil, enabled: Bool = true, posture: SavedExecutionPosture,
         lastFired: Date? = nil, lastRunID: UUID? = nil) {
        self.id = id; self.name = name; self.trigger = trigger; self.prompt = prompt
        self.agentID = agentID; self.enabled = enabled; self.posture = posture
        self.lastFired = lastFired; self.lastRunID = lastRunID
    }

    // Forward-compatible decode (wave-1 idiom). `id`/`name`/`trigger`/`prompt`/`posture`
    // are required identity; the rest tolerate absence.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        trigger = try c.decode(ScheduleTrigger.self, forKey: .trigger)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        agentID = try c.decodeIfPresent(UUID.self, forKey: .agentID)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        posture = try c.decode(SavedExecutionPosture.self, forKey: .posture)
        lastFired = try c.decodeIfPresent(Date.self, forKey: .lastFired)
        lastRunID = try c.decodeIfPresent(UUID.self, forKey: .lastRunID)
    }
}

struct SchedulesDocument: PersistableDocument {
    static let documentID = "agent-schedules"
    var schedules: [AgentSchedule] = []

    init(schedules: [AgentSchedule] = []) { self.schedules = schedules }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schedules = try c.decodeIfPresent([AgentSchedule].self, forKey: .schedules) ?? []
    }
}
