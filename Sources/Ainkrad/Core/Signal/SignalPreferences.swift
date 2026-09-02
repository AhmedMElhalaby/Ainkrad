import Foundation
import AinkradAppKit
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

extension AppEnvironment {
    /// `~/Library/Application Support/<bundle-id>/signal.sqlite`.
    ///
    /// Beside `Cache/`, not inside it: the feed is the record rather than a
    /// derived index, so a cache purge must not erase the user's history. And
    /// deliberately not under the user's Ainkrad Home - it is machine state,
    /// not vault data, the same reasoning that puts `DevPlugins` under the
    /// cache root.
    static func signalStoreURL(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("signal.sqlite")
    }

    /// The external-ingress socket.
    ///
    /// Delegates to `SignalSocketPath` in `AinkradSignal` rather than building
    /// the path here: `ainkrad notify` derives the same path from that same
    /// definition, and two independent constructions of a path with no
    /// discovery step between them is exactly how a socket ends up bound
    /// somewhere the CLI never looks.
    static func signalSocketURL(bundleID: String? = nil) -> URL {
        SignalSocketPath.default(bundleID: bundleID
            ?? Bundle.main.bundleIdentifier
            ?? "com.ainkrad.app")
    }

    /// Builds the center, degrading to memory if the store cannot be opened.
    /// A notification subsystem that prevents the app from launching is worse
    /// than no notification subsystem.
    @MainActor
    static func makeSignalCenter(storeURL: URL,
                                 preferences: SignalPreferences,
                                 sound: (any SoundPlaying)? = nil,
                                 toast: SignalToastModel = SignalToastModel(),
                                 contextProvider: HostDeliveryContextProvider
                                    = HostDeliveryContextProvider(),
                                 badge: @escaping (SignalSource) -> Void = { _ in })
    -> SignalCenter {
        let store = try? SignalStore(url: storeURL)
        let dispatcher = DeliveryDispatcher(
            banner: UserNotificationBannerChannel(),
            toast: toast,
            sound: sound ?? SilentSoundPlayer(),
            badge: badge)
        let center = SignalCenter(store: store,
                                  deliverer: dispatcher,
                                  contextProvider: contextProvider,
                                  rules: preferences.rules,
                                  retention: preferences.retention)
        // SignalCenter's reference to its deliverer is weak; nothing else owns
        // the dispatcher, so the center must.
        center.retainDeliverer(dispatcher)

        if store == nil {
            center.emit(SignalDraft(kind: "signal.degraded", severity: .warning,
                                    title: "Notification history unavailable",
                                    body: "Events are being kept in memory only for this session.",
                                    dedupeKey: "signal:degraded"), from: .host)
        }
        return center
    }
}

/// Stands in when no sound engine is available (tests, and the window between
/// the center being built and the engine existing). Silence is the correct
/// fallback: an alert nobody asked for is worse than a missing chime.
@MainActor
final class SilentSoundPlayer: SoundPlaying {
    func play(_ sound: UISound) {}
    func preview(_ effect: UISound) {}
}
