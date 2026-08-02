import Foundation

struct ScryRect: Codable, Equatable, Sendable {
    var x: Double, y: Double, width: Double, height: Double
    static let defaultCard = ScryRect(x: 40, y: 40, width: 360, height: 240)

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    // Forward-compatible decode (wave-1 idiom): every field tolerates absence.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? ScryRect.defaultCard.x
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? ScryRect.defaultCard.y
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? ScryRect.defaultCard.width
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? ScryRect.defaultCard.height
    }
}

/// Typed scry element kinds. Unknown raw strings decode to `.unknown` so a
/// document written by a newer build never crashes an older one (additive schema).
enum ScryElementKind: String, Codable, Sendable, CaseIterable {
    case text, markdown, table, diagram, chart, image, video, audio, code, status, card, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ScryElementKind(rawValue: raw) ?? .unknown
    }
}

struct ScryElement: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var kind: ScryElementKind
    var title: String?
    var body: String
    var language: String?
    var rect: ScryRect
    var z: Int
    var pinned: Bool

    init(id: String, kind: ScryElementKind, title: String? = nil, body: String,
         language: String? = nil, rect: ScryRect = .defaultCard, z: Int = 0,
         pinned: Bool = false) {
        self.id = id; self.kind = kind; self.title = title; self.body = body
        self.language = language; self.rect = rect; self.z = z; self.pinned = pinned
    }

    // Forward-compatible decode (wave-1 idiom). `id` is required identity;
    // every other field tolerates absence so a newer-schema document never
    // fails to load on an older build.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(ScryElementKind.self, forKey: .kind) ?? .unknown
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language)
        rect = try c.decodeIfPresent(ScryRect.self, forKey: .rect) ?? .defaultCard
        z = try c.decodeIfPresent(Int.self, forKey: .z) ?? 0
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}
