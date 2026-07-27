import os

/// Module-local mirror of the host app's `Log` enum (`Sources/Ainkrad/Core/Logging/Log.swift`).
/// `AinkradHostRuntime` cannot import the app (dependencies only flow app →
/// module), so the plugin-runtime code that used to log through the app's
/// shared `Log` facade gets its own copy here — same subsystem and category
/// strings, so Console.app filtering and log output are unchanged. Only the
/// categories the moved files actually use are mirrored.
enum Log {
    private static let subsystem = "com.ainkrad.app"

    static let registry = Logger(subsystem: subsystem, category: "registry")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
