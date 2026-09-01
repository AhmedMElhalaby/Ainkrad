import Foundation
import AinkradSignal

struct SignalPreferences: Codable, Equatable {
    var rules: RoutingRules
    var retention: RetentionPolicy

    init(rules: RoutingRules = .default, retention: RetentionPolicy = .default) {
        self.rules = rules
        self.retention = retention
    }
}

/// JSON on disk. Notification preferences are small, hand-inspectable and
/// worth being readable when something goes wrong; they do not belong in the
/// SQLite feed, whose rows are evictable and these are not.
struct SignalPreferencesStore {
    let url: URL

    func load() -> SignalPreferences {
        guard let data = try? Data(contentsOf: url),
              let prefs = try? JSONDecoder().decode(SignalPreferences.self, from: data)
        else { return SignalPreferences() }
        return prefs
    }

    func save(_ prefs: SignalPreferences) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
