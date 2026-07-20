import Foundation
import Speech

/// Guards a `CheckedContinuation` against SFSpeech's `recognitionTask` calling its
/// completion handler more than once (partial results + a final result, or a late
/// error after completion). The handler fires on SFSpeech's private queue, so the
/// guard must be its own lock rather than a captured `var` in the closure.
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<TranscriptionResult, Error>

    init(_ continuation: CheckedContinuation<TranscriptionResult, Error>) {
        self.continuation = continuation
    }

    func resume(returning result: TranscriptionResult) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: result)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(throwing: error)
    }
}

/// Apple on-device speech recognition. Private + offline — audio never leaves
/// the machine. The availability gate is unit-tested; the recognition path
/// requires the Speech entitlement + a downloaded model and is manual-gated.
struct OnDeviceTranscriptionBackend: TranscriptionService {
    let availability: SpeechRecognizerAvailability

    init(availability: SpeechRecognizerAvailability = AppleSpeechAvailability()) {
        self.availability = availability
    }

    func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
        let locale = localeIdentifier ?? "en-US"
        guard availability.isAvailable(localeIdentifier: locale) else {
            throw TranscriptionError.unavailable("On-device speech unavailable for \(locale)")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            throw TranscriptionError.unavailable(locale)
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString)-\(fileName)")
        try audio.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let request = SFSpeechURLRecognitionRequest(url: tmp)
        request.requiresOnDeviceRecognition = true

        return try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.resume(throwing: TranscriptionError.provider(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    box.resume(returning: TranscriptionResult(
                        text: result.bestTranscription.formattedString, isFinal: true))
                }
            }
        }
    }
}
