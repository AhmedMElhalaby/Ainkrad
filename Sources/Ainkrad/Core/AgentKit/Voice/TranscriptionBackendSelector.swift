import Foundation

struct ResolvedBackend {
    let service: TranscriptionService
    let kind: TranscriptionBackendKind
    let notice: String?
}

@MainActor
struct TranscriptionBackendSelector {
    let settings: VoiceSettingsStore
    let onDevice: TranscriptionService
    let providerFactory: () -> TranscriptionService?
    let availability: SpeechRecognizerAvailability

    func resolve() throws -> ResolvedBackend {
        let doc = settings.document
        let provider = (doc.providerOptIn ? providerFactory() : nil)

        switch doc.backend {
        case .provider:
            guard doc.providerOptIn else { throw TranscriptionError.notOptedIn }
            guard let provider else { throw TranscriptionError.noConnection }
            return ResolvedBackend(service: provider, kind: .provider, notice: nil)

        case .onDevice:
            if availability.isAvailable(localeIdentifier: doc.localeIdentifier) {
                return ResolvedBackend(service: onDevice, kind: .onDevice, notice: nil)
            }
            if let provider {
                return ResolvedBackend(
                    service: provider, kind: .provider,
                    notice: "On-device speech is unavailable for \(doc.localeIdentifier); using provider STT.")
            }
            throw TranscriptionError.unavailable(doc.localeIdentifier)
        }
    }
}
