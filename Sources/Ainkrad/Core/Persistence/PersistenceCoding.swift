import Foundation

/// The single JSON coder configuration used across the persistence layer, so
/// on-disk documents, the in-memory store, and export bundles all round-trip
/// identically. ISO-8601 dates keep envelopes human-readable; sorted keys make
/// output deterministic (useful for tests and the future sync seam).
enum PersistenceCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
