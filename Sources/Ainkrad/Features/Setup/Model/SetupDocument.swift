import Foundation
import AinkradHostRuntime

/// Records that first-run setup finished, and at which version.
///
/// Versioning is what lets a later release add a step and re-gate on only that
/// step, instead of replaying the whole wizard for existing users.
struct SetupDocument: PersistableDocument {
    static let documentID = "setup"

    var completedAt: Date?
    var setupVersion: Int

    init(completedAt: Date? = nil, setupVersion: Int = 0) {
        self.completedAt = completedAt
        self.setupVersion = setupVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        setupVersion = try c.decodeIfPresent(Int.self, forKey: .setupVersion) ?? 0
    }

    enum CodingKeys: String, CodingKey { case completedAt, setupVersion }
}
