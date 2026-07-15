import Foundation
import Observation
import AinkradAppKit

/// One app's surface appearance. `surfaceOpacity` is honored only for
/// host-background apps (the Assistant); every app honors `blurEnabled`.
struct AppAppearanceEntry: Codable, Equatable {
    var surfaceOpacity: Double = 1.0
    var blurEnabled: Bool = false
    /// User override of the app's presentation, as `PluginPresentation.rawValue`.
    /// `nil` = use the bundle's declared default. Applies on next open.
    var presentationOverride: String? = nil
}

/// Per-app surface appearance, keyed by `appID` (the Assistant is one surface
/// among many now — Terminal, Git Mage, and any plugin have their own entry).
struct AppAppearanceDocument: PersistableDocument {
    static let documentID = "app-appearance"
    var entries: [String: AppAppearanceEntry] = [:]
}

/// The Slice-2c Assistant-only document. Retained ONLY so a first load can
/// migrate the user's existing Assistant opacity/blur into the `"assistant"`
/// entry of the per-app store. Not `private` so the migration test can seed it.
struct LegacyAssistantAppearanceDocument: PersistableDocument {
    static let documentID = "assistant-appearance"
    var surfaceOpacity: Double
    var blurEnabled: Bool

    init(surfaceOpacity: Double = 1.0, blurEnabled: Bool = false) {
        self.surfaceOpacity = surfaceOpacity
        self.blurEnabled = blurEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surfaceOpacity = try c.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? 1.0
        blurEnabled = try c.decodeIfPresent(Bool.self, forKey: .blurEnabled) ?? false
    }
}

/// Observable per-app appearance store. Same load/mutate/save pattern as the
/// other settings stores; opacity setter clamps to `0…1`.
@MainActor
@Observable
final class AppAppearanceStore {
    private var document: AppAppearanceDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        var doc = persistence.load(AppAppearanceDocument.self) ?? AppAppearanceDocument()
        // One-time migration: fold the Slice-2c Assistant-only store into the
        // per-app map so the user's current Assistant opacity/blur carries over.
        if doc.entries["assistant"] == nil,
           let legacy = persistence.load(LegacyAssistantAppearanceDocument.self) {
            doc.entries["assistant"] = AppAppearanceEntry(
                surfaceOpacity: legacy.surfaceOpacity, blurEnabled: legacy.blurEnabled)
            persistence.save(doc)
        }
        self.document = doc
    }

    func blurEnabled(_ appID: String) -> Bool { document.entries[appID]?.blurEnabled ?? false }
    func surfaceOpacity(_ appID: String) -> Double { document.entries[appID]?.surfaceOpacity ?? 1.0 }

    func setBlurEnabled(_ appID: String, _ isOn: Bool) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.blurEnabled = isOn
        document.entries[appID] = entry
        persistence.save(document)
    }

    func setSurfaceOpacity(_ appID: String, _ value: Double) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.surfaceOpacity = min(max(value, 0), 1)
        document.entries[appID] = entry
        persistence.save(document)
    }

    func presentationOverride(_ appID: String) -> PluginPresentation? {
        document.entries[appID]?.presentationOverride.flatMap(PluginPresentation.init(rawValue:))
    }

    func setPresentationOverride(_ appID: String, _ value: PluginPresentation?) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.presentationOverride = value?.rawValue
        document.entries[appID] = entry
        persistence.save(document)
    }
}
