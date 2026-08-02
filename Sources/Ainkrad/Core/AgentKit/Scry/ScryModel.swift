import Foundation
import AinkradHostRuntime

struct ScryModel: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    var elements: [ScryElement] = []

    init(elements: [ScryElement] = []) { self.elements = elements }

    // Forward-compatible decode (wave-1 idiom): every field tolerates absence.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elements = try c.decodeIfPresent([ScryElement].self, forKey: .elements) ?? []
    }

    /// Z-ascending (back-to-front), stable for equal z.
    var ordered: [ScryElement] {
        elements.enumerated()
            .sorted { $0.element.z != $1.element.z ? $0.element.z < $1.element.z : $0.offset < $1.offset }
            .map(\.element)
    }

    var nextZ: Int { (elements.map(\.z).max() ?? -1) + 1 }

    mutating func upsert(_ element: ScryElement) {
        if let i = elements.firstIndex(where: { $0.id == element.id }) {
            elements[i] = element
        } else {
            elements.append(element)
        }
    }

    mutating func remove(id: String) { elements.removeAll { $0.id == id } }
}

struct ScryWorkspaceDocument: PersistableDocument {
    static let documentID = "agent-canvas"
    var version = ScryModel.schemaVersion
    var canvases: [String: ScryModel] = [:]

    init(version: Int = ScryModel.schemaVersion, canvases: [String: ScryModel] = [:]) {
        self.version = version
        self.canvases = canvases
    }

    // Hand-written forward-compatible decode (wave-1 global constraint,
    // ground-truth gotcha #11): every field decodeIfPresent + default so a
    // document written by a newer build never fails to load on an older one.
    enum CodingKeys: String, CodingKey { case version, canvases }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? ScryModel.schemaVersion
        self.canvases = try c.decodeIfPresent([String: ScryModel].self, forKey: .canvases) ?? [:]
    }
}
