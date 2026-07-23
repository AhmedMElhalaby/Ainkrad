import Foundation

/// A value that can be persisted as a standalone, versioned document.
/// `documentID` is the file stem and cache key; `currentSchemaVersion` is the
/// version this build writes; `migrators` upgrade older on-disk payloads.
public protocol PersistableDocument: Codable, Equatable {
    static var documentID: String { get }
    static var currentSchemaVersion: Int { get }
    static var migrators: [DocumentMigrator] { get }
}

extension PersistableDocument {
    public static var currentSchemaVersion: Int { 1 }
    public static var migrators: [DocumentMigrator] { [] }
}

/// Transforms a document payload from `fromVersion` to `fromVersion + 1`.
public struct DocumentMigrator {
    let fromVersion: Int
    let migrate: (JSONValue) -> JSONValue

    public init(from fromVersion: Int, _ migrate: @escaping (JSONValue) -> JSONValue) {
        self.fromVersion = fromVersion
        self.migrate = migrate
    }
}
