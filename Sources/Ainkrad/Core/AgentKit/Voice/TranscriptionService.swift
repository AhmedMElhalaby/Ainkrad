import Foundation

/// File-based speech-to-text. Push-to-talk captures to a temp file then calls
/// this on stop; dropped audio calls it directly. Live streaming partials are a
/// screenshot-gated nicety layered on top, not part of this seam.
/// `@MainActor` because the provider backend reads the @MainActor ConnectionStore
/// (a nonisolated requirement can't be satisfied by a @MainActor witness in Swift 6).
@MainActor
protocol TranscriptionService {
    func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult
}
