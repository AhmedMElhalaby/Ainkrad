import Foundation
import Observation
import AinkradHostRuntime

/// Persisted choice of image/media generation provider. The API key itself never
/// lives here — it's Keychain-only via `SecretStore` (`OpenAIImageBackend.secretID`).
struct MediaSettingsDocument: PersistableDocument {
    static let documentID = "media.settings"
    var provider: String = "openai"
}

/// Backs the Assistant Settings MEDIA section's provider picker. Mirrors
/// `WebSearchSettingsStore`: loads the persisted document at init, writes
/// through on every setter call.
@MainActor
@Observable
final class MediaSettingsStore {
    private(set) var document: MediaSettingsDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(MediaSettingsDocument.self) ?? MediaSettingsDocument()
    }

    func setProvider(_ id: String) {
        document.provider = id
        persistence.save(document)
    }
}
