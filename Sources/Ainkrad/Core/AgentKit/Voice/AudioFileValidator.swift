import Foundation

enum AudioFileValidator {
    /// Extensions accepted by both Apple Speech and OpenAI-compatible Whisper.
    static let allowedExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aiff", "aif", "caf", "flac",
        "mp4", "mpeg", "mpga", "webm", "ogg", "oga",
    ]
    /// OpenAI's Whisper endpoint caps uploads at 25 MB; use the same ceiling for both backends.
    static let maxBytes = 25 * 1024 * 1024

    static func validate(fileName: String, byteCount: Int) throws {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw TranscriptionError.unsupportedFormat(ext.isEmpty ? fileName : ext)
        }
        guard byteCount <= maxBytes else {
            throw TranscriptionError.tooLarge(byteCount)
        }
    }
}
