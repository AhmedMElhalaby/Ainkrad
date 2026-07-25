import Foundation

/// Parses the comma-separated redaction field used by BOTH the export modal
/// and the share modal, so the two flows redact identically. Trims whitespace
/// and drops empty entries.
enum RedactionList {
    static func parse(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Replaces every redaction string in `text` with `[redacted]`. Shared by the
    /// renderer and the share flow so a secret is stripped BEFORE any truncation —
    /// truncating first could leave a partial secret that no longer matches.
    static func apply(_ redactions: [String], to text: String) -> String {
        redactions.reduce(text) { $0.replacingOccurrences(of: $1, with: "[redacted]") }
    }
}
