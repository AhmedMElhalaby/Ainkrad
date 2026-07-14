import Foundation
import Observation

/// Per-Assistant surface appearance: opacity of the Assistant Block's own
/// background and whether it sits over a blur so the workspace shows through.
/// Its own persisted document (not the shared overlay settings) — the Assistant
/// is one surface, so this is global rather than per-workspace.
struct AssistantAppearanceDocument: PersistableDocument {
    static let documentID = "assistant-appearance"

    /// 0 = fully transparent, 1 = fully opaque. Default 1.0 (no change for
    /// existing users until they dial it).
    var surfaceOpacity: Double = 1.0
    /// When true, a blur sits behind the Assistant surface (workspace shows
    /// through where opacity < 1). Default off.
    var blurEnabled: Bool = false

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

/// Observable store over `AssistantAppearanceDocument`. Same load/mutate/save
/// pattern as `AgentPermissionStore`; `setSurfaceOpacity` clamps to `0…1`.
@MainActor
@Observable
final class AssistantAppearanceStore {
    private var document: AssistantAppearanceDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(AssistantAppearanceDocument.self) ?? AssistantAppearanceDocument()
    }

    var surfaceOpacity: Double { document.surfaceOpacity }
    var blurEnabled: Bool { document.blurEnabled }

    func setSurfaceOpacity(_ value: Double) {
        document.surfaceOpacity = min(max(value, 0), 1)
        persistence.save(document)
    }

    func setBlurEnabled(_ isOn: Bool) {
        document.blurEnabled = isOn
        persistence.save(document)
    }
}
