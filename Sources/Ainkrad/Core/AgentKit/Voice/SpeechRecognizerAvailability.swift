import Foundation
import Speech

protocol SpeechRecognizerAvailability: Sendable {
    func isAvailable(localeIdentifier: String) -> Bool
}

struct AppleSpeechAvailability: SpeechRecognizerAvailability {
    func isAvailable(localeIdentifier: String) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            return false
        }
        return recognizer.isAvailable
    }
}
