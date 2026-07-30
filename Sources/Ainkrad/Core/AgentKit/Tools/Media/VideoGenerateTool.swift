import Foundation
import AinkradHostRuntime

/// Generates a video from a prompt, writes it to disk, and renders it as a
/// `video` card on the Live Canvas (body = a `file:` URL). Read-class + reversible
/// (it draws a card and writes a scratch file; the paid network call is the only
/// meaningful side effect, gated by the approval backstop). Video generation is
/// slow, so the tool may take a while to return.
struct VideoGenerateTool: AgentTool {
    let backend: any VideoBackend
    let store: CanvasStore
    let mediaStore: GeneratedMediaStore

    let name = "video_generate"
    let description = "Generate a short video from a text prompt and render it as a video card on the Live Canvas."
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "prompt": .object(["type": .string("string"),
                                   "description": .string("Text description of the video to generate.")]),
                "title": .object(["type": .string("string"),
                                  "description": .string("Optional card title.")]),
            ]),
            "required": .array([.string("prompt")]),
        ])
    }

    @MainActor
    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let prompt = input["prompt"]?.stringValue, !prompt.isEmpty else {
            throw ToolError.message("video_generate requires a non-empty \"prompt\".")
        }
        guard backend.isConfigured else {
            return ToolResult(
                content: "Video generation is not configured. Add a provider API key in Settings → Assistant → Video.",
                isError: false)
        }
        let video = try await backend.generateVideo(prompt: prompt)
        let fileURL = try mediaStore.write(video.data, fileExtension: video.fileExtension)
        let element = CanvasElement(
            id: UUID().uuidString, kind: .video,
            title: input["title"]?.stringValue ?? prompt, body: fileURL.absoluteString)
        let id = store.add(element)
        return ToolResult(content: "Rendered generated video as canvas element \(id).", isError: false)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        ToolApprovalPreview(title: "Generate video", summary: input["prompt"]?.stringValue ?? "?", diff: nil)
    }

    func isIrreversible(_ input: JSONValue) -> Bool { false }
}
