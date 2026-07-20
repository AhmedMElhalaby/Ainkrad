import Foundation
import Testing
@testable import Ainkrad

@Suite("PushToTalkController")
@MainActor
struct PushToTalkControllerTests {
    private struct EchoService: TranscriptionService {
        func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
            TranscriptionResult(text: "transcribed")
        }
    }

    private func make(mode: PushToTalkMode = .hold, autoSend: Bool = false,
                      mic: MicAuthorization = .authorized, grant: Bool = true)
    -> (PushToTalkController, FakeCaptureSession) {
        let settings = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setMode(mode); settings.setAutoSend(autoSend)
        let capture = FakeCaptureSession()
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: EchoService(),
            providerFactory: { nil }, availability: AlwaysAvailable())
        let controller = PushToTalkController(
            settings: settings, capture: capture,
            permission: FakeMicPermission(status: mic, grantOnRequest: grant),
            selector: selector, readAudio: { _ in Data("A".utf8) })
        return (controller, capture)
    }

    private struct AlwaysAvailable: SpeechRecognizerAvailability {
        func isAvailable(localeIdentifier: String) -> Bool { true }
    }

    /// A mic-permission fake whose `request()` stays in flight until manually resolved,
    /// so tests can control the exact interleaving of press/release vs. grant resolution.
    /// `waitUntilRequested()` only returns once the grant continuation is actually stored,
    /// so `resolveRequest(granted:)` is guaranteed to resume a live continuation — no blind
    /// `Task.yield()` guessing, and no risk of resolving before anyone is listening (which
    /// would leak the continuation and hang the caller forever).
    private final class DeferredMicPermission: MicPermissionProviding, @unchecked Sendable {
        private(set) var status: MicAuthorization = .notDetermined
        private var grantContinuation: CheckedContinuation<Bool, Never>?
        private var requestedContinuation: CheckedContinuation<Void, Never>?
        private var hasBeenRequested = false

        func request() async -> Bool {
            await withCheckedContinuation { cont in
                self.grantContinuation = cont
                self.hasBeenRequested = true
                self.requestedContinuation?.resume()
                self.requestedContinuation = nil
            }
        }

        /// Suspends until `request()` has been called and its continuation is live.
        func waitUntilRequested() async {
            if hasBeenRequested { return }
            await withCheckedContinuation { self.requestedContinuation = $0 }
        }

        func resolveRequest(granted: Bool) {
            status = granted ? .authorized : .denied
            grantContinuation?.resume(returning: granted)
            grantContinuation = nil
        }
    }

    @Test func holdRecordsWhilePressed() async {
        let (c, capture) = make(mode: .hold)
        var review: String?
        c.onTranscript = { review = $0 }
        c.pressStarted()
        #expect(capture.isRecording)
        #expect(c.status == .recording)
        c.pressEnded()
        await c.awaitPendingForTesting()
        #expect(!capture.isRecording)
        #expect(review == "transcribed")
        #expect(c.status == .idle)
    }

    @Test func toggleStartsThenStops() async {
        let (c, capture) = make(mode: .toggle)
        c.pressStarted()                 // start
        #expect(capture.isRecording)
        c.pressEnded()                   // ignored in toggle
        #expect(capture.isRecording)
        c.pressStarted()                 // stop + transcribe
        await c.awaitPendingForTesting()
        #expect(!capture.isRecording)
    }

    @Test func autoSendRoutesToSendSink() async {
        let (c, _) = make(mode: .hold, autoSend: true)
        var sent: String?
        c.onAutoSend = { sent = $0 }
        c.pressStarted(); c.pressEnded()
        await c.awaitPendingForTesting()
        #expect(sent == "transcribed")
    }

    @Test func micDeniedRaisesPermissionNeeded() async {
        let (c, capture) = make(mic: .denied, grant: false)
        var needed = false
        c.onPermissionNeeded = { needed = true }
        c.pressStarted()
        await c.awaitPendingForTesting()
        #expect(needed)
        #expect(!capture.isRecording)
    }

    @Test func interruptionStopsAndTranscribesPartial() async {
        let (c, capture) = make(mode: .hold)
        var review: String?
        c.onTranscript = { review = $0 }
        c.pressStarted()
        c.handleInterruption()
        await c.awaitPendingForTesting()
        #expect(!capture.isRecording)
        #expect(review == "transcribed")
    }

    @Test(.timeLimit(.minutes(1)))
    func holdReleaseBeforeGrantNeverStartsCapture() async {
        let settings = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setMode(.hold)
        let capture = FakeCaptureSession()
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: EchoService(),
            providerFactory: { nil }, availability: AlwaysAvailable())
        let mic = DeferredMicPermission()
        let c = PushToTalkController(
            settings: settings, capture: capture, permission: mic,
            selector: selector, readAudio: { _ in Data("A".utf8) })
        var transcript: String?
        c.onTranscript = { transcript = $0 }

        c.pressStarted()                 // notDetermined -> spawns permission-request Task
        await mic.waitUntilRequested()    // deterministic: grant continuation is now live
        c.pressEnded()                    // released BEFORE the grant resolves
        mic.resolveRequest(granted: true) // grant arrives after release
        await c.awaitPendingForTesting()

        #expect(!capture.isRecording)
        #expect(transcript == nil)
        #expect(c.status == .idle)
    }

    @Test(.timeLimit(.minutes(1)))
    func holdGrantResolvesWhileStillHeldStartsCapture() async {
        let settings = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setMode(.hold)
        let capture = FakeCaptureSession()
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: EchoService(),
            providerFactory: { nil }, availability: AlwaysAvailable())
        let mic = DeferredMicPermission()
        let c = PushToTalkController(
            settings: settings, capture: capture, permission: mic,
            selector: selector, readAudio: { _ in Data("A".utf8) })

        c.pressStarted()                 // notDetermined -> spawns permission-request Task
        await mic.waitUntilRequested()    // deterministic: grant continuation is now live
        mic.resolveRequest(granted: true) // grant arrives while the key is still held
        await c.awaitPendingForTesting()

        #expect(capture.isRecording)
        #expect(c.status == .recording)
    }
}
