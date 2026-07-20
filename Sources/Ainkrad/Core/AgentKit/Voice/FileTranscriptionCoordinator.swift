import Foundation

@MainActor
final class FileTranscriptionCoordinator {
    private let selector: TranscriptionBackendSelector
    private let slicer: AudioSlicer
    private let maxChunk: Double

    init(selector: TranscriptionBackendSelector, slicer: AudioSlicer, maxChunk: Double = 120) {
        self.selector = selector
        self.slicer = slicer
        self.maxChunk = maxChunk
    }

    func transcribe(fileURL: URL, byteCount: Int, progress: @escaping (Double) -> Void) async throws -> String {
        try AudioFileValidator.validate(fileName: fileURL.lastPathComponent, byteCount: byteCount)
        let resolved = try selector.resolve()
        let total = try await slicer.duration(of: fileURL)
        let chunks = AudioChunker.plan(totalDuration: total, maxChunk: maxChunk)

        if chunks.count <= 1 {
            let audio = try Data(contentsOf: fileURL)
            let result = try await resolved.service.transcribe(
                audio: audio, fileName: fileURL.lastPathComponent, localeIdentifier: nil)
            progress(1.0)
            return result.text
        }

        var parts: [String] = []
        for chunk in chunks {
            let data = try await slicer.slice(fileURL, chunk: chunk)
            let result = try await resolved.service.transcribe(
                audio: data, fileName: "chunk-\(chunk.index).m4a", localeIdentifier: nil)
            parts.append(result.text)
            progress(Double(chunk.index + 1) / Double(chunks.count))
        }
        return parts.joined(separator: " ")
    }
}
