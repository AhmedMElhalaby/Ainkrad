import Foundation
import Testing
@testable import Ainkrad

private struct StubAvailability: SpeechRecognizerAvailability {
    let available: Bool
    func isAvailable(localeIdentifier: String) -> Bool { available }
}

@Suite("OnDeviceTranscriptionBackend availability")
@MainActor
struct SpeechRecognizerAvailabilityTests {
    @Test func unavailableLocaleThrows() async {
        let backend = OnDeviceTranscriptionBackend(availability: StubAvailability(available: false))
        await #expect(throws: TranscriptionError.self) {
            _ = try await backend.transcribe(audio: Data("A".utf8), fileName: "m.m4a", localeIdentifier: "zz-ZZ")
        }
    }
}
