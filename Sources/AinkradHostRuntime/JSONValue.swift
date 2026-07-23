import Foundation

/// A structural representation of arbitrary JSON. Used to inspect and migrate
/// a document payload without decoding it into a concrete type, and to carry
/// opaque document bodies through export/import.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    /// All JSON numbers are represented as `Double`, so an integer field routed
    /// through `JSONValue` (migration/export) round-trips via `Double` — safe
    /// for values under 2^53, but a future Int64-range field would lose precision.
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    /// Convert to a Foundation object graph for `JSONSerialization`-built request bodies.
    public func toFoundationObject() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map { $0.toFoundationObject() }
        case .object(let o): return o.mapValues { $0.toFoundationObject() }
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    /// Parse a JSON string (e.g. an OpenAI tool `arguments` string, or accumulated
    /// Claude `partial_json`). Returns nil on malformed input.
    public static func parse(_ string: String) -> JSONValue? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Inverse of `toFoundationObject()` — lifts a Foundation JSON value
    /// (from `JSONSerialization`) into a `JSONValue`.
    public static func fromFoundationObject(_ object: Any) -> JSONValue {
        switch object {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let n as Int: return .number(Double(n))
        case let n as Double: return .number(n)
        case let n as NSNumber: return .number(n.doubleValue)
        case let a as [Any]: return .array(a.map(fromFoundationObject))
        case let d as [String: Any]: return .object(d.mapValues(fromFoundationObject))
        default: return .null
        }
    }
}
