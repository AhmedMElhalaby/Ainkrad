import os

/// Central `os.Logger` categories — one per module, all under the app's
/// subsystem, so Console.app can filter per area. See AIN-45.
enum Log {
    private static let subsystem = "com.ainkrad.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let registry = Logger(subsystem: subsystem, category: "registry")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let terminal = Logger(subsystem: subsystem, category: "terminal")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
