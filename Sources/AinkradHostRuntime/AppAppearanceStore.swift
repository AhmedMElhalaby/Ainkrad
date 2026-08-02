import Foundation
import Observation
import AinkradAppKit

/// One app's surface appearance. `surfaceOpacity` is honored only for
/// host-background apps (the Assistant); every app honors `blurEnabled`.
public struct AppAppearanceEntry: Codable, Equatable {
    public var surfaceOpacity: Double = 1.0
    public var blurEnabled: Bool = false
    /// User override of the app's presentation, as `PluginPresentation.rawValue`.
    /// `nil` = use the bundle's declared default. Applies on next open.
    public var presentationOverride: String? = nil
    /// Per-app font overrides, as `UIFontFamily` / `UIFontScale` raw values.
    /// `nil` = inherit the global Appearance setting.
    public var fontFamily: String? = nil
    public var fontScale: String? = nil

    public init(surfaceOpacity: Double = 1.0, blurEnabled: Bool = false,
                presentationOverride: String? = nil, fontFamily: String? = nil, fontScale: String? = nil) {
        self.surfaceOpacity = surfaceOpacity
        self.blurEnabled = blurEnabled
        self.presentationOverride = presentationOverride
        self.fontFamily = fontFamily
        self.fontScale = fontScale
    }
}

/// Per-app surface appearance, keyed by `appID` (the Assistant is one surface
/// among many now — Terminal, Git Mage, and any plugin have their own entry).
public struct AppAppearanceDocument: PersistableDocument {
    public static let documentID = "app-appearance"
    public static let currentSchemaVersion = 2

    /// v1 → v2: the 2026-08-02 app rename. Entries keyed by the retired ids
    /// (`assistant`, `canvas`, `files`, `terminal`) move to their new ids so a
    /// user's opacity, blur, presentation override and per-app fonts survive.
    public static let migrators: [DocumentMigrator] = [
        DocumentMigrator(from: 1) { payload in
            guard case .object(var root) = payload,
                  case .object(let entries)? = root["entries"] else { return payload }
            root["entries"] = .object(AppIDRenames.rekeyed(entries))
            return .object(root)
        },
    ]

    public var entries: [String: AppAppearanceEntry] = [:]

    public init(entries: [String: AppAppearanceEntry] = [:]) {
        self.entries = entries
    }
}

/// The Slice-2c Assistant-only document. Retained ONLY so a first load can
/// migrate the user's existing Assistant opacity/blur into the `"assistant"`
/// entry of the per-app store. Not `private` so the migration test can seed it.
public struct LegacyAssistantAppearanceDocument: PersistableDocument {
    public static let documentID = "assistant-appearance"
    public var surfaceOpacity: Double
    public var blurEnabled: Bool

    public init(surfaceOpacity: Double = 1.0, blurEnabled: Bool = false) {
        self.surfaceOpacity = surfaceOpacity
        self.blurEnabled = blurEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surfaceOpacity = try c.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? 1.0
        blurEnabled = try c.decodeIfPresent(Bool.self, forKey: .blurEnabled) ?? false
    }
}

/// Observable per-app appearance store. Same load/mutate/save pattern as the
/// other settings stores; opacity setter clamps to `0…1`.
@MainActor
@Observable
public final class AppAppearanceStore {
    private var document: AppAppearanceDocument
    private let persistence: PersistenceStore

    public init(persistence: PersistenceStore) {
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

    public func blurEnabled(_ appID: String) -> Bool { document.entries[appID]?.blurEnabled ?? false }
    public func surfaceOpacity(_ appID: String) -> Double { document.entries[appID]?.surfaceOpacity ?? 1.0 }

    public func setBlurEnabled(_ appID: String, _ isOn: Bool) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.blurEnabled = isOn
        document.entries[appID] = entry
        persistence.save(document)
    }

    public func setSurfaceOpacity(_ appID: String, _ value: Double) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.surfaceOpacity = min(max(value, 0), 1)
        document.entries[appID] = entry
        persistence.save(document)
    }

    public func presentationOverride(_ appID: String) -> PluginPresentation? {
        document.entries[appID]?.presentationOverride.flatMap(PluginPresentation.init(rawValue:))
    }

    public func setPresentationOverride(_ appID: String, _ value: PluginPresentation?) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.presentationOverride = value?.rawValue
        document.entries[appID] = entry
        persistence.save(document)
    }

    public func fontFamily(_ appID: String) -> UIFontFamily? {
        document.entries[appID]?.fontFamily.flatMap(UIFontFamily.init(rawValue:))
    }

    public func setFontFamily(_ appID: String, _ value: UIFontFamily?) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.fontFamily = value?.rawValue
        document.entries[appID] = entry
        persistence.save(document)
    }

    public func fontScale(_ appID: String) -> UIFontScale? {
        document.entries[appID]?.fontScale.flatMap(UIFontScale.init(rawValue:))
    }

    public func setFontScale(_ appID: String, _ value: UIFontScale?) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.fontScale = value?.rawValue
        document.entries[appID] = entry
        persistence.save(document)
    }
}
