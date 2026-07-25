import Foundation

/// A generated image: a sniffed MIME type + raw bytes base64-encoded, matching
/// `AgentContentBlock.image(mediaType:base64:)`'s convention.
struct GeneratedImage: Equatable, Sendable {
    let mediaType: String
    let base64: String
}

/// Pluggable image-generation provider. `isConfigured == false` drives the
/// graceful "not configured" path in `ImageGenerateTool` (never an error).
protocol MediaBackend: Sendable {
    var isConfigured: Bool { get }
    func generateImage(prompt: String) async throws -> GeneratedImage
}
