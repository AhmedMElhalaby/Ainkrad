/// Get/set persistence for Codable values by key. The one deliberate
/// persistence seam for M1 — see ADR-0003 Persistence & Settings Storage.
protocol SettingsStore {
    func get<T: Codable>(_ type: T.Type, forKey key: String) -> T?
    func set<T: Codable>(_ value: T, forKey key: String)
}
