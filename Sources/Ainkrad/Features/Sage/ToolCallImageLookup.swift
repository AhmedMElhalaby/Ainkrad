import Foundation

/// Resolves the image an `image_generate` tool call rendered, so the transcript
/// card can show it inline. The tool stores the image as a canvas element (to
/// avoid flooding the model with a base64 `data:` URL — the model-facing result
/// stays a short sentence naming the element id). This looks that element back
/// up from the id embedded in the result text.
@MainActor
enum ToolCallImageLookup {
    /// The `data:` image body of the canvas element named in an `image_generate`
    /// result, or `nil` if not found / not an image.
    static func canvasImageDataURL(resultText: String?, store: CanvasStore) -> String? {
        canvasBody(resultText: resultText, store: store, kind: .image)
    }

    /// The `file:`/`http:` video URL of the canvas element named in a
    /// `video_generate` result, or `nil` if not found / not a video.
    static func canvasVideoURL(resultText: String?, store: CanvasStore) -> String? {
        canvasBody(resultText: resultText, store: store, kind: .video)
    }

    /// The `file:` audio URL of the canvas element named in a `speak` result,
    /// or `nil` if not found / not audio.
    static func canvasAudioURL(resultText: String?, store: CanvasStore) -> String? {
        canvasBody(resultText: resultText, store: store, kind: .audio)
    }

    private static func canvasBody(resultText: String?, store: CanvasStore, kind: CanvasElementKind) -> String? {
        guard let text = resultText, let id = firstUUID(in: text) else { return nil }
        guard let element = store.model.elements.first(where: { $0.id == id }), element.kind == kind
        else { return nil }
        return element.body
    }

    /// First RFC-4122-shaped UUID substring in `text`. Pure and testable.
    static func firstUUID(in text: String) -> String? {
        let pattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }
}
