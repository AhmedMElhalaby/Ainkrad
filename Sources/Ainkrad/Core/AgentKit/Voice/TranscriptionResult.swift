import Foundation

struct TranscriptionResult: Equatable, Sendable {
    let text: String
    let isFinal: Bool
    init(text: String, isFinal: Bool = true) {
        self.text = text
        self.isFinal = isFinal
    }
}

enum TranscriptionError: Error, Equatable {
    case noConnection
    case notOptedIn
    case unavailable(String)
    case unsupportedFormat(String)
    case tooLarge(Int)
    case provider(String)
}
