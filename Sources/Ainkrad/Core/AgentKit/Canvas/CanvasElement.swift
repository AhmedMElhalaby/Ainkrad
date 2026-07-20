import Foundation

struct CanvasRect: Codable, Equatable, Sendable {
    var x: Double, y: Double, width: Double, height: Double
    static let defaultCard = CanvasRect(x: 40, y: 40, width: 360, height: 240)

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    // Forward-compatible decode (wave-1 idiom): every field tolerates absence.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? CanvasRect.defaultCard.x
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? CanvasRect.defaultCard.y
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? CanvasRect.defaultCard.width
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? CanvasRect.defaultCard.height
    }
}

/// Typed canvas element kinds. Unknown raw strings decode to `.unknown` so a
/// document written by a newer build never crashes an older one (additive schema).
enum CanvasElementKind: String, Codable, Sendable, CaseIterable {
    case text, markdown, table, diagram, chart, image, code, status, card, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CanvasElementKind(rawValue: raw) ?? .unknown
    }
}

struct CanvasElement: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var kind: CanvasElementKind
    var title: String?
    var body: String
    var language: String?
    var rect: CanvasRect
    var z: Int
    var pinned: Bool

    init(id: String, kind: CanvasElementKind, title: String? = nil, body: String,
         language: String? = nil, rect: CanvasRect = .defaultCard, z: Int = 0,
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
        kind = try c.decodeIfPresent(CanvasElementKind.self, forKey: .kind) ?? .unknown
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language)
        rect = try c.decodeIfPresent(CanvasRect.self, forKey: .rect) ?? .defaultCard
        z = try c.decodeIfPresent(Int.self, forKey: .z) ?? 0
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}
